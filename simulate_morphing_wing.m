function results = simulate_morphing_wing(inputs, performance)
%SIMULATE_MORPHING_WING One actuation run of the SMA-driven morphing section.
%
%   results = SIMULATE_MORPHING_WING(inputs, performance) runs one actuation of
%   the design in INPUTS, as built by build_morphing_inputs, against the
%   structural-battery performance map in PERFORMANCE.  The battery is the rigid
%   root; only the polymer hinge outboard of it bends.
%
%   The run is in four parts, in this order:
%     1. the pack and the section are described (buildBatteryState,
%        buildSectionState);
%     2. the circuit and the three-node thermal network are marched through the
%        actuation window, giving the wire temperature history;
%     3. that history is turned into how far the wires have transformed, and so
%        into the deflection of the hinge;
%     4. the headline numbers are collected (buildSummary).
%
%   All geometry comes from INPUTS.  This file contains no geometry of its own.

arguments
    inputs (1,1) struct
    performance (1,1) struct
end

sma = inputs.sma;
thermal = inputs.thermal;
battery = buildBatteryState(inputs.battery, performance, sma);
section = buildSectionState(inputs);

dt = inputs.simulation.dt_s;
time = 0:dt:inputs.simulation.totalTime_s;
n = numel(time);

% One value per time step, for every quantity the run has to carry forward.
%   wire/sleeve/bulk temperature  the three thermal nodes
%   current_A                     drawn from the pack
%   wirePower_W                   dissipated in the wires, which is also what
%                                 leaves the pack terminals
%   internalLossPower_W           dissipated inside the cells instead
%   batteryPower_W                the sum of the two, taken from the chemistry
%   energyRemaining_Wh            what is left of the usable energy
[wireTemperature_C, sleeveTemperature_C, bulkTemperature_C, current_A, ...
    wirePower_W, batteryPower_W, internalLossPower_W, energyRemaining_Wh] = ...
    deal(zeros(1, n));

temperatures_C = thermal.ambientTemperature_C * ones(3, 1);
wireTemperature_C(1) = temperatures_C(1);
sleeveTemperature_C(1) = temperatures_C(2);
bulkTemperature_C(1) = temperatures_C(3);
energyRemaining_Wh(1) = battery.availableEnergy_Wh;

% Three-node conduction: wire -> sleeve of polymer -> bulk of the hinge.  The
% network never changes during a run, so the backward-Euler update
%     (I - dt*rates) * T_next = T + dt * heatInput
% is inverted once here, leaving one matrix-vector product per time step.  That
% is unconditionally stable and conserves energy exactly over each step.
heatCapacity_JpK = [thermal.wireThermalMass_JpK; ...
    max(thermal.sleeveThermalMass_JpK, eps); max(thermal.bulkThermalMass_JpK, eps)];
exchange = [thermal.wireToSleeveConductance_WpK, thermal.sleeveToBulkConductance_WpK];
rates = zeros(3);
for node = 1:2
    rates(node, node) = rates(node, node) - exchange(node) / heatCapacity_JpK(node);
    rates(node, node + 1) = exchange(node) / heatCapacity_JpK(node);
    rates(node + 1, node) = exchange(node) / heatCapacity_JpK(node + 1);
    rates(node + 1, node + 1) = rates(node + 1, node + 1) - ...
        exchange(node) / heatCapacity_JpK(node + 1);
end
stepMatrix = (eye(3) - dt * rates) \ eye(3);
heatingColumn = stepMatrix(:, 1) * dt / heatCapacity_JpK(1);

% Energy only limits the run in power mode, where the pack sits at a C-rate the
% performance map covers.  In resistance mode the current is set by Ohm's law and
% the C-rate lands far outside the map, where no measured capacity exists, so the
% pack is held at its full-charge EMF and never cut off for lack of energy.  The
% energy drawn is still tracked, for reporting only.
tracksEnergy = strcmp(battery.driveMode, 'power');

for k = 1:n
    % Electrical circuit.
    wireResistance_Ohm = max(sma.circuitResistance_Ohm * (1 + ...
        sma.resistanceTempCoeff_1pK * ...
        (wireTemperature_C(k) - sma.referenceTemperature_C)), eps);
    loopResistance_Ohm = wireResistance_Ohm;

    isActuating = time(k) >= inputs.simulation.actuationStart_s && ...
        time(k) <= inputs.simulation.actuationStop_s && ...
        (~tracksEnergy || energyRemaining_Wh(k) > battery.minimumReserve_Wh);

    if isActuating && strcmp(battery.driveMode, 'power')
        % Two ceilings bind at once.  The wires cannot be passed more than the
        % rated power, and the pack cannot source more than the current that
        % power represents at its terminal voltage.  A high resistance network
        % is power limited, a low resistance one is current limited, and the
        % two coincide when R_wire = V_pack^2 / P.
        %
        % No third ceiling at V_pack / R_wire is imposed.  The map's voltage is
        % measured under load at the rated C-rate, so it is not the voltage that
        % drives the current: at a lower draw the cell would sit nearer its
        % open-circuit value.  Past R_wire = V_pack^2 / P the current here does
        % imply a terminal voltage above the rated one, which in a built design
        % would have to come from cells in series.
        current_A(k) = min(sqrt(battery.powerLimit_W / wireResistance_Ohm), ...
            battery.currentCeiling_A);
    elseif isActuating
        % One loop: pack EMF across the pack resistance and the wire network.
        loopResistance_Ohm = wireResistance_Ohm + battery.packResistance_Ohm;
        current_A(k) = battery.packVoltage_V / loopResistance_Ohm;
    end

    % Never draw more than the usable energy left in this step.
    requestedEnergy_Wh = current_A(k)^2 * loopResistance_Ohm * dt / 3600;
    usableEnergy_Wh = max(energyRemaining_Wh(k) - battery.minimumReserve_Wh, 0);
    if tracksEnergy && requestedEnergy_Wh > usableEnergy_Wh && requestedEnergy_Wh > 0
        current_A(k) = current_A(k) * sqrt(usableEnergy_Wh / requestedEnergy_Wh);
    end

    % Where the power goes.  The pack draws I^2*(R_wire + R_pack) from its
    % chemistry; the share against R_pack is lost inside the cells and never
    % leaves them.  What reaches the wires, I^2*R_wire, is also what a
    % galvanostatic charge-discharge measurement would record at the terminals.
    wirePower_W(k) = current_A(k)^2 * wireResistance_Ohm;
    batteryPower_W(k) = current_A(k)^2 * loopResistance_Ohm;
    internalLossPower_W(k) = current_A(k)^2 * battery.packResistance_Ohm * isActuating;

    if k == n
        break
    end

    % One implicit step of the three-node network.
    temperatures_C = stepMatrix * temperatures_C + ...
        heatingColumn * (thermal.heatingEfficiency * wirePower_W(k));
    wireTemperature_C(k + 1) = temperatures_C(1);
    sleeveTemperature_C(k + 1) = temperatures_C(2);
    bulkTemperature_C(k + 1) = temperatures_C(3);

    energyRemaining_Wh(k + 1) = max(energyRemaining_Wh(k) - ...
        batteryPower_W(k) * dt / 3600, battery.minimumReserve_Wh);
end

% Structural response.  Nothing in the heating depends on how far the hinge has
% bent, so it is worked out once the thermal run is done.  The wires pull in
% proportion to how far they have transformed until they run out of
% contraction; from then on the hinge keeps the shape it had reached.  Each
% distinct load is evaluated once, since most steps sit at no load or full load.
activationFraction = smaActivation(wireTemperature_C, ...
    sma.activationStart_C, sma.activationFinish_C);
[loads, ~, whichLoad] = unique(min(activationFraction, section.loadCeiling));
[loadDeflections_m, loadRotations_rad] = tipDeflection(section, loads);
deflection_m = reshape(loadDeflections_m(whichLoad), 1, []);
tipRotation_rad = reshape(loadRotations_rad(whichLoad), 1, []);

results.time_s = time;
results.wireTemperature_C = wireTemperature_C;
results.sleeveTemperature_C = sleeveTemperature_C;
results.bulkTemperature_C = bulkTemperature_C;
results.current_A = current_A;
results.internalLossPower_W = internalLossPower_W;
results.wirePower_W = wirePower_W;
results.batteryPower_W = batteryPower_W;
results.deflection_m = deflection_m;
results.tipRotation_rad = tipRotation_rad;
results.activationFraction = activationFraction;
results.energyRemaining_Wh = energyRemaining_Wh;
results.inputs = inputs;
results.battery = battery;
results.section = section;
results.summary = buildSummary(results);

if inputs.simulation.plotResults
    plotMorphingResults(results);
    plotMorphingSideView(results);
end
end

function battery = buildBatteryState(inputsBattery, performance, sma)
%BUILDBATTERYSTATE Mass, usable energy and circuit properties of the pack.
% Mass follows the developed electrode area: the planform of one cell times the
% number stacked, at the areal density of the laminate.
totalArea_m2 = inputsBattery.planformArea_m2 * inputsBattery.cellCount;
battery.totalMass_kg = totalArea_m2 * inputsBattery.compositeArealDensity_kgpm2;

% Pack Thevenin equivalent, already assembled in build_morphing_inputs.
battery.packVoltage_V = inputsBattery.packVoltage_V;
battery.packResistance_Ohm = inputsBattery.packResistance_Ohm;

battery.driveMode = char(lower(string(inputsBattery.driveMode)));
switch battery.driveMode
    case 'power'
        % The pack is described by what the performance map says it delivers at
        % the chosen C-rate.  That measurement is taken at the terminals, so the
        % internal loss is already inside it: the pack resistance is therefore
        % set to zero here rather than counted a second time in the circuit.
        battery.operatingCRate = inputsBattery.powerCRate;
        battery.packResistance_Ohm = 0;
    case 'resistance'
        % Usable energy depends on C-rate, and C-rate is the circuit current
        % divided by a capacity that itself depends on the energy, so the two
        % are solved together.
        battery.operatingCRate = solveOperatingCRate( ...
            inputsBattery, performance, battery.totalMass_kg, sma);
    otherwise
        error('Unknown battery driveMode "%s". Use resistance or power.', ...
            battery.driveMode);
end
battery.performanceMapCRate = min(max(battery.operatingCRate, ...
    min(performance.cRate)), max(performance.cRate));
battery.cRateOutsidePerformanceMap = ...
    battery.operatingCRate < min(performance.cRate) || ...
    battery.operatingCRate > max(performance.cRate);

battery.availableEnergy_Wh = battery.totalMass_kg * interp1(performance.cRate, ...
    performance.totalMass.energyDensity_WhPerKg, battery.performanceMapCRate, 'linear');
battery.powerLimit_W = battery.totalMass_kg * interp1(performance.cRate, ...
    performance.totalMass.powerDensity_WPerKg, battery.performanceMapCRate, 'linear');
% The rated power is also a current ceiling: at a fixed terminal voltage the
% pack cannot source more than powerLimit/packVoltage amps, however little
% resistance the wires present.
battery.currentCeiling_A = battery.powerLimit_W / battery.packVoltage_V;
battery.minimumReserve_Wh = inputsBattery.reserveEnergyFraction * battery.availableEnergy_Wh;
end

function cRate = solveOperatingCRate(inputsBattery, performance, totalMass_kg, sma)
%SOLVEOPERATINGCRATE Fixed-point solve of C-rate against the performance map.
%   Usable energy depends on the C-rate and the C-rate depends on the current
%   divided by the capacity that energy gives, so the two settle together.
current_A = inputsBattery.packVoltage_V / ...
    (sma.circuitResistance_Ohm + inputsBattery.packResistance_Ohm);

cRate = max(inputsBattery.operatingCRate, eps);
for i = 1:50
    mapCRate = min(max(cRate, min(performance.cRate)), max(performance.cRate));
    capacity_Ah = totalMass_kg * interp1(performance.cRate, ...
        performance.totalMass.energyDensity_WhPerKg, mapCRate, 'linear') / ...
        inputsBattery.packVoltage_V;
    nextCRate = current_A / max(capacity_Ah, eps);
    converged = abs(nextCRate - cRate) <= 1e-6 * max(nextCRate, 1);
    cRate = nextCRate;
    if converged
        break
    end
end
end

function section = buildSectionState(inputs)
%BUILDSECTIONSTATE How the section resists, and what the wires can do to it.
%   The section is described station by station along the deflecting span, from
%   the root (0) to the tip (1), because on a tapered hinge neither the
%   stiffness nor the moment is constant.  Everything is worked out for the wires
%   pulling with their full force; tipDeflection scales it to any fraction.
sma = inputs.sma;
p = inputs.polymer;
width_m = inputs.battery.width_m;
section.station = p.spanStation;

% The battery is the rigid root and cannot deflect.  Only the polymer hinge
% outboard of it folds, so the hinge is the whole deflecting span and its own
% free end is the tip.  Both the bending stiffness of the polymer and the moment
% arm of the wires follow the taper, station by station.
section.label = sprintf('Soft hinge (%s side profile), battery stays rigid', ...
    p.sideProfile);
section.length_m = p.hingeLength_m;
wireLength_m = p.wireLength_m;
EI = p.modulus_Pa * width_m * p.thicknessAlongSpan_m.^3 / 12;
arm_m = p.wireArmAlongSpan_m;

% What resists.  A wire that is transforming delivers its plateau stress rather
% than behaving elastically, so the active wires do not fight their own moment.
% The bias wires stay martensitic and do resist.  Being part of the section, they
% stiffen it in bending in proportion to the square of their offset, which
% follows the taper like everything else.
biasStiffness_N = sma.biasWireCount * sma.wireArea_m2 * sma.youngModulusMartensite_Pa;
EI = EI + biasStiffness_N * arm_m.^2;

% What the wires do at full force.  A pull along a line offset from the neutral
% axis is a bending moment plus a compression along the axis.  The compression
% is taken by a thin, axially stiff layer on the neutral axis, to whose ends the
% wires are anchored; lying on the axis, it adds almost nothing to EI.  The
% polymer is therefore left with the moment alone.
force_N = sma.wireCount * sma.pullForcePerWire_N;
section.curvatureFull_pm = force_N * arm_m ./ EI;

% Stroke limit.  The wire slides freely between its anchors, so only its total
% shortening is limited: what the bending costs at the wire's offset.  That grows
% in proportion to the pull, so the wire runs out of contraction at this
% fraction of its full force.  Past it the hinge cannot follow.
wireShorteningFull_m = section.length_m * trapz(section.station, ...
    section.curvatureFull_pm .* arm_m);
section.strokeLoadFraction = sma.recoverableStrain * wireLength_m / wireShorteningFull_m;

% Rotation limit.  The tip is not allowed to turn past maxTipRotation_deg: the
% wires are pre-strained so that their stroke ends there, or an end stop or the
% controller holds them.  The slope grows in proportion to the pull, so the limit
% is another load fraction, and whichever comes first ends the actuation.
rotationFull_rad = section.length_m * trapz(section.station, section.curvatureFull_pm);
section.loadCeiling = min(section.strokeLoadFraction, ...
    deg2rad(p.maxTipRotation_deg) / rotationFull_rad);

% The furthest the tip can get.  Up to 90 degrees the tip rises steadily with
% the load; with a limit set higher, a thin hinge could curl its tip past the
% vertical and start bringing it back, so this is the peak along the way.
section.maxDeflection_m = max(tipDeflection(section, ...
    linspace(0, section.loadCeiling, 121)));
end

function [deflection_m, rotation_rad] = tipDeflection(section, loadFractions)
%TIPDEFLECTION Tip rise and rotation with the wires at fractions of full force.
%   The curvature follows the moment station by station and the slope is its
%   running integral; the tip rises by the integral of sin(slope) along the arc.
%   Nothing here assumes the rotation is small.  One result per load fraction,
%   each load worked on its own row.
a = loadFractions(:);
slope_rad = a .* section.length_m .* cumtrapz(section.station, section.curvatureFull_pm, 2);
deflection_m = section.length_m * trapz(section.station, sin(slope_rad), 2);
rotation_rad = slope_rad(:, end);
end

function a = smaActivation(T, Tstart, Tfinish)
a = min(max((T - Tstart) / (Tfinish - Tstart), 0), 1);
end

function summary = buildSummary(results)
%BUILDSUMMARY The headline numbers of one run, in the units the studies quote.
%   Every field here is either read by minimal_requirements_study or printed for
%   a single case by run_morphing_case; the full time histories stay in RESULTS.
[peakDeflection_m, idxPeak] = max(results.deflection_m);
usedEnergy_Wh = results.battery.availableEnergy_Wh - results.energyRemaining_Wh(end);

% What the hinge did.
summary.peakDeflection_mm = 1e3 * peakDeflection_m;
summary.maxDeflection_mm = 1e3 * results.section.maxDeflection_m;   % ceiling of this hinge
summary.strokeFraction = peakDeflection_m / max(results.section.maxDeflection_m, eps);
summary.peakRotation_deg = rad2deg(results.tipRotation_rad(idxPeak));

% How far the wires got, and how hard they were driven.
summary.peakActivationFraction = max(results.activationFraction);   % 1 = fully transformed
summary.peakTemperature_C = max(results.wireTemperature_C);
summary.peakCurrent_A = max(results.current_A);
summary.peakWirePower_W = max(results.wirePower_W);

% Energy accounting.  What left the cells is what reached the wires; the rest of
% what the chemistry gave up was dissipated inside the cells.
summary.availableEnergy_Wh = results.battery.availableEnergy_Wh;
summary.deliveredEnergy_Wh = trapz(results.time_s, results.wirePower_W) / 3600;
summary.internalLossEnergy_Wh = trapz(results.time_s, results.internalLossPower_W) / 3600;
summary.deliveryEfficiency = summary.deliveredEnergy_Wh / max(usedEnergy_Wh, eps);

% The circuit and the pack, as the studies report them.
summary.wireResistance_Ohm = results.inputs.sma.circuitResistance_Ohm;
summary.packResistance_Ohm = results.battery.packResistance_Ohm;
summary.packVoltage_V = results.battery.packVoltage_V;
summary.batteryCurrentCeiling_A = results.battery.currentCeiling_A;  % power mode only
summary.batteryOperatingCRate = results.battery.operatingCRate;
summary.cRateOutsidePerformanceMap = results.battery.cRateOutsidePerformanceMap;
summary.batteryMass_g = 1e3 * results.battery.totalMass_kg;
end

function plotMorphingResults(results)
figure('Name', 'Morphing wing', 'Color', 'w', ...
    'Position', [80 80 1000 850]);
tiledlayout(3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile
yyaxis left
plot(results.time_s, 1e3 * results.deflection_m, 'LineWidth', 1.8)
ylabel('Deflection (mm)')
yyaxis right
plot(results.time_s, results.energyRemaining_Wh, 'LineWidth', 1.8)
ylabel('Energy remaining (Wh)')
grid on
xlabel('Time (s)')
title(results.section.label)

nexttile
plot(results.time_s, results.wireTemperature_C, 'LineWidth', 1.8)
hold on
plot(results.time_s, results.sleeveTemperature_C, 'LineWidth', 1.4)
plot(results.time_s, results.bulkTemperature_C, 'LineWidth', 1.2)
yline(results.inputs.sma.activationStart_C, '--', 'Actuation start')
yline(results.inputs.sma.activationFinish_C, '--', 'Actuation finish')
grid on
xlabel('Time (s)')
ylabel('Temperature (C)')
% Outside, on the right, where the other tiles carry their right-hand axes.
legend('SMA wire', 'Polymer sleeve', 'Bulk hinge', 'Location', 'eastoutside')

nexttile
yyaxis left
plot(results.time_s, results.current_A, 'LineWidth', 1.8)
ylabel('Current (A)')
yyaxis right
plot(results.time_s, results.activationFraction, 'LineWidth', 1.8)
ylabel('Activation fraction (-)')
ylim([0 1.05])
grid on
xlabel('Time (s)')

end

function plotMorphingSideView(results)
p = results.inputs.polymer;
b = results.inputs.battery;
hingeStart_m = b.length_m;                          % rigid battery, then the hinge
totalLength_m = hingeStart_m + p.hingeLength_m;
peakDeflection_m = max(results.deflection_m);

figure('Name', 'Morphing structure side view', 'Color', 'w', ...
    'Position', [80 80 1300 500]);
hold on

patch(1e3 * [0 hingeStart_m hingeStart_m 0], ...
    1e3 * 0.5 * [-b.totalThickness_m -b.totalThickness_m b.totalThickness_m b.totalThickness_m], ...
    [0.82 0.84 0.80], 'EdgeColor', [0.25 0.27 0.25], 'LineWidth', 1.2, ...
    'DisplayName', 'Battery stack (rigid root)');

tip_m = p.thicknessAlongSpan_m(end);
polymerX = 1e3 * [hingeStart_m totalLength_m totalLength_m hingeStart_m];
polymerY = 1e3 * 0.5 * [-p.thickness_m -tip_m tip_m p.thickness_m];
patch(polymerX, polymerY, [0.70 0.88 0.95], 'EdgeColor', [0.10 0.35 0.45], ...
    'LineWidth', 1.4, 'DisplayName', 'Polymer hinge (deflects)');

wireX = 1e3 * [hingeStart_m totalLength_m];
plot(wireX, 1e3 * [p.wireRootOffset_m 0], 'r-', 'LineWidth', 2.0, ...
    'DisplayName', 'Active SMA wires')
if results.inputs.sma.biasWireCount > 0
    plot(wireX, 1e3 * [-p.wireRootOffset_m 0], 'Color', [0.45 0.10 0.10], ...
        'LineWidth', 1.5, 'DisplayName', 'Bias SMA wires')
end
plot(1e3 * [0 totalLength_m], [0 0], 'k:', 'LineWidth', 1.0, ...
    'DisplayName', 'Neutral axis')

if peakDeflection_m > 0
    plot(1e3 * [totalLength_m totalLength_m], 1e3 * [0 peakDeflection_m], ...
        'Color', [0.00 0.45 0.20], 'LineWidth', 1.6, 'DisplayName', 'Peak tip deflection')
end

axis equal
grid on
halfRange_m = max([0.06 * totalLength_m, 0.75 * p.thickness_m, 1.2 * peakDeflection_m]);
xlim(1e3 * [-0.02 * totalLength_m, 1.05 * totalLength_m])
ylim(1e3 * [-halfRange_m, halfRange_m])
xlabel('Chordwise position (mm)')
ylabel('Thickness direction (mm)')
title('True-scale side view of the model geometry')
legend('Location', 'southoutside', 'NumColumns', 3)
end
