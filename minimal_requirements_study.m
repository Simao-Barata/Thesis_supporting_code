% MINIMAL_REQUIREMENTS_STUDY  How many wires, wired how, on what battery, with or without bias.
%
%   Everything the concept can reasonably be allowed to move is swept here:
%       - how many wires, and every series/parallel way of wiring them
%       - with bias wires and without
%       - cell area, cells stacked, and every series/parallel way of wiring those
%       - a few representative ASR values
%
%   Cell AREA is swept by changing the length only.  The hinge is as wide as the
%   cell and its stiffness goes as that width, so widening the cell would stiffen
%   the structure and confound the electrical question; changing length moves the
%   area and the internal resistance and nothing else.
%
%   What the figures report is AREA, because that is what decides whether the
%   concept fits in a wing at all, and it is a question the structural design
%   cannot argue away.  The area quoted is always the area of ONE cell, which is
%   the footprint of the whole stack: stacked cells sit on top of each other and
%   share a planform, so that is the area the wing has to give up, whatever the
%   stack height.  Two figures answer two different questions:
%
%     the footprint at which a stack stops getting better, and how far it bends
%     there.  Deflection climbs with area, because a bigger cell has a lower
%     internal resistance and passes more current, until either the wires are
%     fully transformed or the hinge runs out of stroke.  Past that point more
%     battery buys nothing, so the useful number is the smallest area that
%     reaches the plateau.
%
%     the footprint at which a single wire of a given diameter can be brought to
%     full transformation at all.  This is the floor below which nothing works,
%     found by bisection on area rather than on the sweep grid.
%
%   The share of the stroke each hinge allows is still carried in the saved
%   tables and the printed report; it is just not what the figures are about.
%   Cell capacity is not the question at this stage.

clear; clc; close all;

%% Settings
%   driveMode selects which of the two studies runs.
%     'resistance'  the pack is an EMF behind its own internal resistance, so
%                   the current follows from Ohm's law and the ASR decides
%                   everything.  Wire diameter is fixed and the ASR is swept.
%     'power'       the delivered power is read from the performance map at
%                   powerCRate.  That figure already excludes what is lost
%                   inside the cells, so the ASR plays no part and is not swept;
%                   wire diameter is swept instead.
driveMode = 'resistance';

wireDiameter_mm = 0.1;                                  % 'resistance' mode only
powerCRate = 1.5;                                       % 'power' mode only
wireCounts = 1:10;                                      % wires on the active side
cellCounts = 1:10;                                      % cells stacked
cellAreas_cm2 = logspace(log10(5), log10(20000), 20);     % 'resistance' mode only
powerCellAreas_cm2 = logspace(log10(20), log10(20000), 20);   % 'power' mode only
areaResistanceProducts_Ohmcm2 = [50 500 2500 5000];  % 'resistance' mode only
% 'resistance' mode only.  How long the current flows in one actuation.  Kept
% short because diffusion, which the ASR leaves out, only builds up after a few
% seconds, and because the thick wires draw close to the pack's short-circuit
% current, which a cell cannot be expected to sustain for long.
actuationTime_s = 5;
biasOptions = [0 1];                                    % bias wires per active wire

performance = battery_performance_data();
catalog = load_wire_catalog();
iWire = find(abs(catalog.diameter_mm - wireDiameter_mm) < 1e-9, 1);
if isempty(iWire)
    error('Wire diameter %.3f mm is not in sma_wire_catalog.csv.', wireDiameter_mm);
end

baseInputs = build_morphing_inputs();
cellWidth_m = baseInputs.battery.width_m;

wireOverrides.sma.wireDiameter_m = catalog.diameter_m(iWire);
wireOverrides.sma.resistancePerMeter_OhmPerM = catalog.resistancePerMeter_OhmPerM(iWire);
wireOverrides.sma.pullForcePerWire_N = catalog.pullForce_N(iWire);

if strcmp(driveMode, 'power')
    runPowerStudy(performance, catalog, powerCRate, wireCounts, ...
        cellCounts, powerCellAreas_cm2, biasOptions, cellWidth_m, baseInputs);
    style_figures();
    return
end

wireOverrides.simulation.actuationStop_s = actuationTime_s;

%% Sweep.  For every wire count and stack height, the best battery and the best
%% wiring of both sides is kept.
nWireCounts = numel(wireCounts);
nAreas = numel(cellAreas_cm2);
nCells = numel(cellCounts);
nAcr = numel(areaResistanceProducts_Ohmcm2);
nBias = numel(biasOptions);
best = cell(nAreas, nCells, nWireCounts, nAcr, nBias);
totalRuns = 0;

fprintf('%.3f mm wire on a %.1f cm wide cell.\n', wireDiameter_mm, 1e2 * cellWidth_m);
fprintf('Sweeping %d wire counts x %d stack heights x %d areas x %d ASR x %d bias options,\n', ...
    nWireCounts, nCells, numel(cellAreas_cm2), nAcr, nBias);
fprintf('each against every series/parallel wiring of both the wires and the cells.\n');

for iBias = 1:nBias
    for iAcr = 1:nAcr
        for iCell = 1:nCells
            cellLayouts = electricalLayouts(cellCounts(iCell));
            for iWires = 1:nWireCounts
                wireLayouts = electricalLayouts(wireCounts(iWires));
                for iArea = 1:nAreas
                    for iCellLayout = 1:size(cellLayouts, 1)
                        for iWireLayout = 1:size(wireLayouts, 1)
                            row = evaluateDesign(performance, wireOverrides, ...
                                cellWidth_m, cellAreas_cm2(iArea), ...
                                areaResistanceProducts_Ohmcm2(iAcr), ...
                                cellLayouts(iCellLayout, :), wireLayouts(iWireLayout, :), ...
                                biasOptions(iBias));
                            totalRuns = totalRuns + 1;
                            if isBetter(row, best{iArea, iCell, iWires, iAcr, iBias})
                                best{iArea, iCell, iWires, iAcr, iBias} = row;
                            end
                        end
                    end
                end
            end
        end
        fprintf('  bias %d, ASR %.0f Ohm.cm2 done (%d runs so far)\n', ...
            biasOptions(iBias), areaResistanceProducts_Ohmcm2(iAcr), totalRuns);
    end
end

bestCases = struct2table([best{:}]);
% area x cells x wires x acr x bias
deflection_mm = reshape(bestCases.peakDeflection_mm, size(best));

% The wire count is not an axis on the figures: at each battery take the wire
% count that bends the section furthest, since that is the design one would
% actually build there.
[bestDeflection_mm, iBestWire] = max(deflection_mm, [], 3);
bestDeflection_mm = squeeze(bestDeflection_mm);      % area x cells x acr x bias
bestWireCount = wireCounts(squeeze(iBestWire));

% The other half of the question, and a separate sweep because it asks about a
% different design: one wire of each catalogue diameter, and the smallest cell
% that can bring it to full transformation.
actuationFloors = singleWireAreaResistance(performance, catalog, ...
    cellWidth_m, cellCounts, biasOptions, areaResistanceProducts_Ohmcm2, actuationTime_s);

printReport(bestCases, wireDiameter_mm, cellWidth_m, baseInputs, totalRuns, ...
    areaResistanceProducts_Ohmcm2, biasOptions);
acrLabels = string(compose('%.0f Ohm.cm^2', areaResistanceProducts_Ohmcm2(:)));
printAreaReport(cellAreas_cm2, cellCounts, bestDeflection_mm, bestWireCount, ...
    actuationFloors, catalog, acrLabels, biasOptions);

assignin('base', 'minimalRequirementsBestCases', bestCases);
save_table(bestCases, 'minimal_requirements_study.csv');
save_table(actuationAreaTable(actuationFloors, catalog, cellCounts, biasOptions, ...
    'areaResistanceProduct_Ohmcm2', areaResistanceProducts_Ohmcm2), ...
    'minimal_requirements_actuation_area.csv');

floorHeadline = 'one active wire, best cell wiring, driven by the pack ASR';
plotAreaForMaxDeflection(cellAreas_cm2, cellCounts, bestDeflection_mm, biasOptions, ...
    acrLabels, sprintf('%.3f mm wire, best wire count at each point', wireDiameter_mm));
plotAreaForFullActuation(actuationFloors, catalog.diameter_mm, cellCounts, ...
    acrLabels, floorHeadline);
plotDeflectionAtActuationFloor(actuationFloors, catalog.diameter_mm, cellCounts, biasOptions, ...
    {'Deflection reached on the smallest planform that fully transforms'; ...
    'one active wire, any ASR'});
plotEndurance(bestCases, areaResistanceProducts_Ohmcm2, biasOptions, ...
    actuationTime_s, max(performance.cRate));
style_figures();

%% ------------------------------------------------------------------------
function row = evaluateDesign(performance, wireOverrides, cellWidth_m, ...
        cellArea_cm2, acr_Ohmcm2, cellLayout, wireLayout, biasPerActive)
overrides = wireOverrides;
overrides.battery.width_m = cellWidth_m;
overrides.battery.length_m = cellArea_cm2 * 1e-4 / cellWidth_m;
overrides.battery.areaResistanceProduct_Ohmcm2 = acr_Ohmcm2;
overrides.battery.cellSeriesCount = cellLayout(1);
overrides.battery.cellParallelCount = cellLayout(2);
overrides.sma.seriesWires = wireLayout(1);
overrides.sma.parallelBranches = wireLayout(2);
overrides.sma.biasWiresPerActiveWire = biasPerActive;

inputs = build_morphing_inputs(overrides);
inputs.simulation.plotResults = false;
inputs.simulation.dt_s = 0.1;
inputs.simulation.totalTime_s = inputs.simulation.actuationStop_s;
results = simulate_morphing_wing(inputs, performance);
summary = results.summary;

row.biasWiresPerActiveWire = biasPerActive;
row.areaResistanceProduct_Ohmcm2 = acr_Ohmcm2;
row.wireCount = inputs.sma.wireCount;
row.wireSeries = inputs.sma.seriesWires;
row.wireParallel = inputs.sma.parallelBranches;
row.wireResistance_Ohm = inputs.sma.circuitResistance_Ohm;
row.cellArea_cm2 = 1e4 * inputs.battery.planformArea_m2;
row.cellLength_cm = 1e2 * inputs.battery.length_m;
row.cellsStacked = inputs.battery.cellCount;
row.cellSeries = inputs.battery.cellSeriesCount;
row.cellParallel = inputs.battery.cellParallelCount;
row.hingeThickness_mm = 1e3 * inputs.polymer.thickness_m;
row.packVoltage_V = inputs.battery.packVoltage_V;
row.packResistance_Ohm = inputs.battery.packResistance_Ohm;
row.current_A = summary.peakCurrent_A;
row.wirePower_W = summary.peakWirePower_W;
row.peakTemperature_C = summary.peakTemperature_C;
row.actuationRatio = summary.peakActivationFraction;
row.peakDeflection_mm = summary.peakDeflection_mm;
row.maxDeflection_mm = summary.maxDeflection_mm;
row.strokeFraction_pct = 100 * summary.strokeFraction;
row.fullyActuated = summary.peakActivationFraction >= 1 && ...
    summary.peakTemperature_C <= inputs.sma.maxWireTemperature_C;

% Endurance.  The tabulated energy density is what a cell delivers at its
% terminals, so the internal loss is already reflected in it and must not be
% charged twice; the energy an actuation costs the store is therefore the
% terminal energy, not the total drawn from the chemistry.  The figure is only
% meaningful where the pack stays inside the C-rate range the data covers.
row.operatingCRate = summary.batteryOperatingCRate;
row.withinDataCRate = summary.batteryOperatingCRate <= max(performance.cRate);
row.batteryMass_g = summary.batteryMass_g;
row.availableEnergy_Wh = summary.availableEnergy_Wh;
row.deliveredEnergy_Wh = summary.deliveredEnergy_Wh;
row.internalLossEnergy_Wh = summary.internalLossEnergy_Wh;
row.deliveryEfficiency_pct = 100 * summary.deliveryEfficiency;
row.actuationsPerCharge = summary.availableEnergy_Wh / max(summary.deliveredEnergy_Wh, eps);
end

function tf = isBetter(row, incumbent)
%ISBETTER Largest share of that hinge's own stroke, then hottest as a tiebreak.
if isempty(incumbent)
    tf = true;
    return
end
candidate = [row.strokeFraction_pct, row.peakTemperature_C];
current = [incumbent.strokeFraction_pct, incumbent.peakTemperature_C];
iDiff = find(candidate ~= current, 1);
tf = ~isempty(iDiff) && candidate(iDiff) > current(iDiff);
end

function layouts = electricalLayouts(count)
%ELECTRICALLAYOUTS Every [series, parallel] pair whose product is COUNT.
series = find(mod(count, 1:count) == 0)';
layouts = [series, count ./ series];
end

function printReport(bestCases, wireDiameter_mm, cellWidth_m, baseInputs, totalRuns, ...
        acrValues, biasOptions)
rule = repmat('=', 1, 78);
fprintf('\n%s\n MINIMAL REQUIREMENTS REPORT  -  %.3f mm wire\n%s\n', rule, wireDiameter_mm, rule);
fprintf(' Ran %d designs. Cell width held at %.1f cm; area, stack height, both\n', ...
    totalRuns, 1e2 * cellWidth_m);
fprintf(' wirings, wire count and bias wires all free.\n');
fprintf(' Actuation needs %.0f C to start and %.0f C to finish.\n', ...
    baseInputs.sma.activationStart_C, baseInputs.sma.activationFinish_C);
fprintf([' Results are the share of the stroke each hinge itself allows, so every\n' ...
    ' point is measured against its own ceiling (a thicker stack has a lower one).\n']);
% Worth stating plainly, because it decides how the maps are read.
oneWire = bestCases(bestCases.wireCount == 1, :);
fprintf([' Note: adding wires never raises the actuation ratio (it splits the current\n' ...
    ' and adds thermal mass), but it does add moment. One wire alone reaches %.1f%%\n' ...
    ' of stroke at best; the maps show what more wires buy where the battery carries them.\n'], ...
    max(oneWire.strokeFraction_pct));

for bias = biasOptions
    if bias == 0
        fprintf('\n WITHOUT BIAS WIRES (the polymer alone returns the section)\n %s\n', ...
            repmat('-', 1, 78));
    else
        fprintf('\n WITH %d BIAS WIRE PER ACTIVE WIRE\n %s\n', bias, repmat('-', 1, 78));
    end
    for acr = acrValues
        subset = bestCases(bestCases.biasWiresPerActiveWire == bias & ...
            bestCases.areaResistanceProduct_Ohmcm2 == acr, :);
        ranked = sortrows(subset, {'strokeFraction_pct', 'peakDeflection_mm'}, ...
            {'descend', 'descend'});
        b = ranked(1, :);
        fprintf('\n  ASR %.0f Ohm.cm^2  ->  best %.1f%% of the stroke available\n', ...
            acr, b.strokeFraction_pct);
        fprintf('    Wires    %d, wired %dS x %dP, %.2f Ohm\n', ...
            b.wireCount, b.wireSeries, b.wireParallel, b.wireResistance_Ohm);
        fprintf('    Battery  %d cells of %.1f cm2, wired %dS x %dP -> %.1f V, %.3f Ohm\n', ...
            b.cellsStacked, b.cellArea_cm2, b.cellSeries, b.cellParallel, ...
            b.packVoltage_V, b.packResistance_Ohm);
        fprintf('    Circuit  %.4f A, %.4f W into the wires, hinge %.1f mm thick\n', ...
            b.current_A, b.wirePower_W, b.hingeThickness_mm);
        fprintf('    Result   %.1f C, actuation %.0f%%, %.2f%% of the %.2f mm stroke\n', ...
            b.peakTemperature_C, 100 * b.actuationRatio, b.strokeFraction_pct, ...
            b.maxDeflection_mm);
    end
end
fprintf('%s\n', rule);
end

function plotEndurance(bestCases, acrValues, biasOptions, strokeTime_s, maxDataCRate)
%PLOTENDURANCE How many strokes a charge is worth, and what that costs in stroke.
%   The left panel shows every design that fully actuates, so the trade against
%   C-rate is visible; the right panel keeps only those inside the range the
%   performance data actually covers, where the endurance figure is trustworthy.
actuating = bestCases(bestCases.fullyActuated, :);
usable = actuating(actuating.withinDataCRate, :);

figure('Name', 'Actuations per charge', 'Color', 'w', 'Position', [80 80 1500 650]);
layout = tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
title(layout, sprintf(['How many %.0f s actuations one charge is worth, ' ...
    'for designs that fully actuate'], strokeTime_s))

nexttile
scatter(actuating.strokeFraction_pct, actuating.actuationsPerCharge, 18, ...
    log10(actuating.operatingCRate), 'filled')
hold on
inRange = actuating.operatingCRate <= maxDataCRate;
scatter(actuating.strokeFraction_pct(inRange), actuating.actuationsPerCharge(inRange), ...
    46, 'k', 'LineWidth', 1.2)
set(gca, 'YScale', 'log')
grid on
c = colorbar;
c.Label.String = 'log_{10} of C-rate';
xlabel('Share of the available stroke delivered (%)')
ylabel('Actuations per charge')
title({'Endurance against deflection, all actuating designs', ...
    sprintf('circled = inside %gC, where the energy data is valid', maxDataCRate)})

nexttile
hold on
colors = lines(numel(acrValues));
markers = {'o', 's'};
for iBias = 1:numel(biasOptions)
    for iAcr = 1:numel(acrValues)
        subset = usable(usable.biasWiresPerActiveWire == biasOptions(iBias) & ...
            usable.areaResistanceProduct_Ohmcm2 == acrValues(iAcr), :);
        if isempty(subset)
            continue
        end
        plot(subset.batteryMass_g, subset.actuationsPerCharge, markers{iBias}, ...
            'Color', colors(iAcr, :), 'MarkerFaceColor', colors(iAcr, :), ...
            'MarkerSize', 6, 'LineStyle', 'none', ...
            'DisplayName', sprintf('%.0f Ohm.cm^2, bias %d', ...
            acrValues(iAcr), biasOptions(iBias)))
    end
end
set(gca, 'YScale', 'log')
grid on
xlabel('Battery mass (g)')
ylabel('Actuations per charge')
title(sprintf('Only the designs inside %gC', maxDataCRate))
if ~isempty(usable)
    legend('Location', 'eastoutside')
end
end

%% ------------------------------------------------------------------------
%  POWER MODE
%  ------------------------------------------------------------------------
function runPowerStudy(performance, catalog, powerCRate, wireCounts, ...
        cellCounts, cellAreas_cm2, biasOptions, cellWidth_m, baseInputs)
%RUNPOWERSTUDY Deflection against battery area, driven by the performance map.
%   The pack delivers whatever the map says it delivers at powerCRate, but it
%   cannot deliver it through any wire network: the current is also held below
%   what the pack's voltage can push through the wires, V_pack / R_wire.  The
%   heating power is therefore min(P, (P/V)^2 R_wire, V^2 / R_wire), which peaks
%   at R_wire = V^2 / P and falls away on both sides, so the wiring of the wires
%   and of the cells both matter and both are swept.  The ASR plays no part,
%   since the rated power is measured at the terminals with the internal loss
%   already taken out.

nDia = height(catalog);
nWires = numel(wireCounts);
nAreas = numel(cellAreas_cm2);
nCells = numel(cellCounts);
nBias = numel(biasOptions);
best = cell(nAreas, nCells, nWires, nBias);   % best over wire diameter
totalRuns = 0;

fprintf('POWER MODE at %gC, %.0f s stroke, cell %.1f cm wide.\n', powerCRate, ...
    baseInputs.simulation.actuationStop_s, 1e2 * cellWidth_m);
fprintf('Sweeping %d diameters x %d wire counts x %d areas x %d stacks x %d bias.\n', ...
    nDia, nWires, nAreas, nCells, nBias);

for iBias = 1:nBias
    for iDia = 1:nDia
        for iWires = 1:nWires
            for iCell = 1:nCells
                for iArea = 1:nAreas
                    row = evaluatePowerDesign(performance, ...
                        catalog(iDia, :), powerCRate, cellWidth_m, ...
                        cellAreas_cm2(iArea), cellCounts(iCell), ...
                        wireCounts(iWires), biasOptions(iBias));
                    totalRuns = totalRuns + 1;
                    incumbent = best{iArea, iCell, iWires, iBias};
                    if isempty(incumbent) || ...
                            row.strokeFraction_pct > incumbent.strokeFraction_pct
                        best{iArea, iCell, iWires, iBias} = row;
                    end
                end
            end
        end
        fprintf('  bias %d, %.3f mm wire done (%d runs)\n', biasOptions(iBias), ...
            catalog.diameter_mm(iDia), totalRuns);
    end
end

bestCases = struct2table([best{:}]);
% area x cells x wires x bias, already best over diameter
deflection_mm = reshape(bestCases.peakDeflection_mm, size(best));

% As in the ASR study, the wire count is collapsed away: at each battery keep
% the wire count that bends the section furthest.
[bestDeflection_mm, iBestWire] = max(deflection_mm, [], 3);
bestDeflection_mm = squeeze(bestDeflection_mm);      % area x cells x bias
bestDeflection_mm = reshape(bestDeflection_mm, ...
    numel(cellAreas_cm2), numel(cellCounts), 1, numel(biasOptions));
bestWireCount = reshape(wireCounts(squeeze(iBestWire)), size(bestDeflection_mm));

actuationFloors = singleWireAreaPower(performance, catalog, ...
    powerCRate, cellWidth_m, cellCounts, biasOptions);

printPowerReport(bestCases, powerCRate, performance, baseInputs, totalRuns);
powerLabel = string(compose('%gC', powerCRate));
printAreaReport(cellAreas_cm2, cellCounts, bestDeflection_mm, bestWireCount, ...
    actuationFloors, catalog, powerLabel, biasOptions);

assignin('base', 'powerStudyCases', bestCases);
save_table(bestCases, 'minimal_requirements_power.csv');
save_table(actuationAreaTable(actuationFloors, catalog, cellCounts, biasOptions, ...
    'powerCRate', powerCRate), 'minimal_requirements_power_actuation_area.csv');

floorHeadline = sprintf('one active wire, pack held at %gC', powerCRate);
plotAreaForMaxDeflection(cellAreas_cm2, cellCounts, bestDeflection_mm, biasOptions, ...
    powerLabel, 'Best wire diameter and wire count at each point');
plotAreaForFullActuation(actuationFloors, catalog.diameter_mm, cellCounts, ...
    powerLabel, floorHeadline);
plotDeflectionAtActuationFloor(actuationFloors, catalog.diameter_mm, cellCounts, biasOptions, ...
    {'Deflection reached on the smallest planform that fully transforms'; ...
    sprintf('one active wire, pack held at %gC', powerCRate)});
end

function row = evaluatePowerDesign(performance, catalogRow, ...
        powerCRate, cellWidth_m, cellArea_cm2, cellCount, wireCount, biasPerActive)
%EVALUATEPOWERDESIGN Best wiring of this design, driven by the performance map.
%   Three ceilings bind the current in power mode: the rated power into the
%   wires, that power at the pack's terminal voltage, and what the pack's own
%   voltage can push through the wires.  The third makes the wiring a real
%   choice: series cells raise the voltage available, series wires raise the
%   resistance it has to overcome, and neither arrangement is best everywhere.
%   Every series/parallel wiring of both sides is therefore tried, and the one
%   that bends the section furthest is kept.
overrides.battery.driveMode = 'power';
overrides.battery.powerCRate = powerCRate;
overrides.battery.width_m = cellWidth_m;
overrides.battery.length_m = cellArea_cm2 * 1e-4 / cellWidth_m;
overrides.sma.wireDiameter_m = catalogRow.diameter_m;
overrides.sma.resistancePerMeter_OhmPerM = catalogRow.resistancePerMeter_OhmPerM;
overrides.sma.pullForcePerWire_N = catalogRow.pullForce_N;
overrides.sma.biasWiresPerActiveWire = biasPerActive;

row = [];
cellLayouts = electricalLayouts(cellCount);
wireLayouts = electricalLayouts(wireCount);
for iCellLayout = 1:size(cellLayouts, 1)
    for iWireLayout = 1:size(wireLayouts, 1)
        overrides.battery.cellSeriesCount = cellLayouts(iCellLayout, 1);
        overrides.battery.cellParallelCount = cellLayouts(iCellLayout, 2);
        overrides.sma.seriesWires = wireLayouts(iWireLayout, 1);
        overrides.sma.parallelBranches = wireLayouts(iWireLayout, 2);
        candidate = onePowerDesign(performance, overrides, catalogRow, ...
            cellCount, wireCount, biasPerActive);
        if isBetter(candidate, row)
            row = candidate;
        end
    end
end
end

function row = onePowerDesign(performance, overrides, catalogRow, ...
        cellCount, wireCount, biasPerActive)
%ONEPOWERDESIGN One run of one wiring, in the power mode.
inputs = build_morphing_inputs(overrides);
inputs.simulation.plotResults = false;
inputs.simulation.dt_s = 0.1;
inputs.simulation.totalTime_s = inputs.simulation.actuationStop_s;
results = simulate_morphing_wing(inputs, performance);
summary = results.summary;

row.biasWiresPerActiveWire = biasPerActive;
row.diameter_mm = catalogRow.diameter_mm;
row.wireCount = wireCount;
row.wireResistance_Ohm = inputs.sma.circuitResistance_Ohm;
row.cellArea_cm2 = 1e4 * inputs.battery.planformArea_m2;
row.cellsStacked = cellCount;
row.hingeThickness_mm = 1e3 * inputs.polymer.thickness_m;
row.batteryMass_g = summary.batteryMass_g;
row.availablePower_W = results.battery.powerLimit_W;
row.currentCeiling_A = summary.batteryCurrentCeiling_A;
row.matchedResistance_Ohm = inputs.battery.packVoltage_V^2 / results.battery.powerLimit_W;
row.availableEnergy_Wh = summary.availableEnergy_Wh;
row.current_A = summary.peakCurrent_A;
row.currentPerWire_A = summary.peakCurrent_A / wireCount;
row.currentVsCatalogRatio = row.currentPerWire_A / catalogRow.referenceCurrent_A;
% Which of the two ceilings actually bound this design.
row.currentLimited = summary.peakCurrent_A >= 0.999 * summary.batteryCurrentCeiling_A;
row.deliveredPower_W = summary.peakCurrent_A^2 * inputs.sma.circuitResistance_Ohm;
row.peakTemperature_C = summary.peakTemperature_C;
row.actuationRatio = summary.peakActivationFraction;
row.peakDeflection_mm = summary.peakDeflection_mm;
row.maxDeflection_mm = summary.maxDeflection_mm;
row.strokeFraction_pct = 100 * summary.strokeFraction;
row.fullyActuated = summary.peakActivationFraction >= 1 && ...
    summary.peakTemperature_C <= inputs.sma.maxWireTemperature_C;
end

function printPowerReport(bestCases, powerCRate, performance, baseInputs, totalRuns)
rule = repmat('=', 1, 78);
stroke_s = baseInputs.simulation.actuationStop_s;
energyDensity = interp1(performance.cRate, ...
    performance.totalMass.energyDensity_WhPerKg, powerCRate);
powerDensity = interp1(performance.cRate, ...
    performance.totalMass.powerDensity_WPerKg, powerCRate);
runtime_min = 60 * energyDensity / powerDensity;

fprintf('\n%s\n POWER-LIMITED STUDY  -  pack held at %gC\n%s\n', rule, powerCRate, rule);
fprintf(' Ran %d designs. Diameter, wire count, cell area, stack height and bias\n', totalRuns);
fprintf(' all swept; the ASR plays no part in this mode.\n\n');
fprintf(' Two ceilings act together.  The pack passes at most its rated power,\n');
fprintf(' and at a fixed %.2f V terminal voltage it sources at most P/V amps.\n', ...
    baseInputs.battery.nominalVoltage_V);
fprintf(' They swap over at R_wire = V^2/P: a network below that resistance is\n');
fprintf(' current starved and never sees the full rated power.\n');
fprintf(' %d of %d stored designs are held by the current ceiling.\n\n', ...
    sum(bestCases.currentLimited), height(bestCases));
fprintf(' At %gC the map gives %.2f Wh/kg against %.2f W/kg, so a charge lasts\n', ...
    powerCRate, energyDensity, powerDensity);
fprintf(' %.0f minutes, or %.0f strokes of %.0f s.  That figure is identical for\n', ...
    runtime_min, runtime_min * 60 / stroke_s, stroke_s);
fprintf(' every design here: runtime is energy over power, which is 1/C hours\n');
fprintf(' whatever the pack weighs.\n');

nFull = sum(bestCases.fullyActuated);
fprintf('\n %d of %d stored designs fully actuate.\n', nFull, height(bestCases));
if nFull == 0
    fprintf(' Best actuation reached anywhere: %.0f%%.\n%s\n', ...
        100 * max(bestCases.actuationRatio), rule);
    return
end

for bias = unique(bestCases.biasWiresPerActiveWire)'
    subset = bestCases(bestCases.biasWiresPerActiveWire == bias & ...
        bestCases.fullyActuated, :);
    fprintf('\n BIAS %d\n %s\n', bias, repmat('-', 1, 78));
    if isempty(subset)
        fprintf('  nothing fully actuates.\n');
        continue
    end
    ranked = sortrows(subset, 'strokeFraction_pct', 'descend');
    b = ranked(1, :);
    fprintf('  best stroke  %.1f%% (%.3f mm of %.2f mm) from %d x %.3f mm wire\n', ...
        b.strokeFraction_pct, b.peakDeflection_mm, b.maxDeflection_mm, ...
        b.wireCount, b.diameter_mm);
    fprintf('               %d cells of %.0f cm2, %.0f g, %.3f W available, %.0f C\n', ...
        b.cellsStacked, b.cellArea_cm2, b.batteryMass_g, b.availablePower_W, ...
        b.peakTemperature_C);
    fprintf('               %.3f A total (ceiling %.3f A), %.2fx the catalogue rating per wire\n', ...
        b.current_A, b.currentCeiling_A, b.currentVsCatalogRatio);
    fprintf('               took %.3f W of the %.3f W offered; wire net %.2f Ohm, matched at %.2f Ohm\n', ...
        b.deliveredPower_W, b.availablePower_W, b.wireResistance_Ohm, ...
        b.matchedResistance_Ohm);
    lightest = sortrows(subset, 'batteryMass_g');
    l = lightest(1, :);
    fprintf('  lightest     %.0f g (%d cells of %.0f cm2) still gives %.1f%% of stroke\n', ...
        l.batteryMass_g, l.cellsStacked, l.cellArea_cm2, l.strokeFraction_pct);
end
fprintf('%s\n', rule);
end

%% ------------------------------------------------------------------------
%  AREA REQUIRED
%  Shared by both modes.  Everything below quotes the area of ONE cell, which
%  is the footprint of the whole stack, because stacked cells share a planform
%  and that footprint is what the wing has to give up.
%  ------------------------------------------------------------------------
function limits_cm2 = actuationAreaSearchLimits()
%ACTUATIONAREASEARCHLIMITS Range of cell areas the bisection is allowed to try.
%   The upper end is a square metre of cell, far past anything this wing could
%   carry: a wire that still cannot be transformed there never will be.
limits_cm2 = [0.5 1e4];
end

function floorPoint = missingFloorPoint()
%MISSINGFLOORPOINT A wire that could not be transformed on any area searched.
floorPoint = struct('area_cm2', NaN, 'deflection_mm', NaN, 'ceiling_mm', NaN);
end

function floors = emptyFloors(varargin)
%EMPTYFLOORS Somewhere to collect the bisection results over a sweep.
floors.area_cm2 = nan(varargin{:});
floors.deflection_mm = nan(varargin{:});
floors.ceiling_mm = nan(varargin{:});
end

function best = keepSmallerArea(best, candidate)
%KEEPSMALLERAREA The cheaper of two floors, tolerating a missing one.
if isnan(best.area_cm2) || (~isnan(candidate.area_cm2) && candidate.area_cm2 < best.area_cm2)
    best = candidate;
end
end

function floorPoint = smallestAreaForFullActuation(overrides, cellWidth_m, performance)
%SMALLESTAREAFORFULLACTUATION Least cell area that fully transforms the wires.
%   Bisection rather than a grid search, because this is a threshold and a grid
%   would only bracket it.  The bisection is valid because activation rises
%   monotonically with area: the area enters the model through the cell's
%   internal resistance in the ASR case and through the rated power in the power
%   case, and nowhere else, so a larger cell always passes more current.  The
%   hinge, the wire and the thermal network do not move with it at all.
%
%   Returns that area, the deflection actually reached on it, and the most that
%   hinge could ever give.  The last two are the point of the exercise: the
%   floor is the cheapest design that works at all, and the gap between what it
%   bends and what the hinge allows is what that thrift costs.
limits_cm2 = actuationAreaSearchLimits();
low_cm2 = limits_cm2(1);
high_cm2 = limits_cm2(2);

summary = summaryAt(high_cm2, overrides, cellWidth_m, performance);
if summary.peakActivationFraction < 1
    floorPoint = missingFloorPoint();
    return
end

summary = summaryAt(low_cm2, overrides, cellWidth_m, performance);
if summary.peakActivationFraction >= 1
    high_cm2 = low_cm2;
else
    for i = 1:18
        mid_cm2 = sqrt(low_cm2 * high_cm2);   % geometric: the search spans decades
        summary = summaryAt(mid_cm2, overrides, cellWidth_m, performance);
        if summary.peakActivationFraction >= 1
            high_cm2 = mid_cm2;
        else
            low_cm2 = mid_cm2;
        end
    end
end

summary = summaryAt(high_cm2, overrides, cellWidth_m, performance);
floorPoint = struct('area_cm2', high_cm2, ...
    'deflection_mm', summary.peakDeflection_mm, ...
    'ceiling_mm', summary.maxDeflection_mm);
end

function summary = summaryAt(area_cm2, overrides, cellWidth_m, performance)
%SUMMARYAT One run of this design on a cell of this area.
overrides.battery.length_m = area_cm2 * 1e-4 / cellWidth_m;
inputs = build_morphing_inputs(overrides);
inputs.simulation.plotResults = false;
inputs.simulation.dt_s = 0.1;
inputs.simulation.totalTime_s = inputs.simulation.actuationStop_s;
results = simulate_morphing_wing(inputs, performance);
summary = results.summary;
end

function overrides = singleWireOverrides(catalogRow, cellWidth_m, biasPerActive)
%SINGLEWIREOVERRIDES One active wire of this diameter, on a cell of this width.
overrides.battery.width_m = cellWidth_m;
overrides.sma.wireDiameter_m = catalogRow.diameter_m;
overrides.sma.resistancePerMeter_OhmPerM = catalogRow.resistancePerMeter_OhmPerM;
overrides.sma.pullForcePerWire_N = catalogRow.pullForce_N;
overrides.sma.seriesWires = 1;
overrides.sma.parallelBranches = 1;
overrides.sma.biasWiresPerActiveWire = biasPerActive;
end

function floors = singleWireAreaResistance(performance, catalog, ...
        cellWidth_m, cellCounts, biasOptions, acrValues, actuationTime_s)
%SINGLEWIREAREARESISTANCE Floor on cell area, one wire, pack driven by its ASR.
%   One active wire is the least a design can ask of the battery: wires in
%   parallel divide the current between them and wires in series need more
%   voltage to pass the same current, so no arrangement of several wires reaches
%   temperature on a smaller cell than one wire alone.  Every way of wiring the
%   cells is tried and the kindest kept, since series cells add EMF but add
%   internal resistance with it and the best compromise moves with stack height.
floors = emptyFloors(height(catalog), numel(cellCounts), numel(acrValues), ...
    numel(biasOptions));
fprintf('\nSingle-wire actuation floor: %d diameters x %d stacks x %d ASR x %d bias.\n', ...
    height(catalog), numel(cellCounts), numel(acrValues), numel(biasOptions));

for iBias = 1:numel(biasOptions)
    for iAcr = 1:numel(acrValues)
        for iCell = 1:numel(cellCounts)
            layouts = electricalLayouts(cellCounts(iCell));
            for iDia = 1:height(catalog)
                overrides = singleWireOverrides(catalog(iDia, :), cellWidth_m, ...
                    biasOptions(iBias));
                overrides.battery.areaResistanceProduct_Ohmcm2 = acrValues(iAcr);
                overrides.simulation.actuationStop_s = actuationTime_s;
                best = missingFloorPoint();
                for iLayout = 1:size(layouts, 1)
                    overrides.battery.cellSeriesCount = layouts(iLayout, 1);
                    overrides.battery.cellParallelCount = layouts(iLayout, 2);
                    best = keepSmallerArea(best, smallestAreaForFullActuation( ...
                        overrides, cellWidth_m, performance));
                end
                floors = storeFloor(floors, best, iDia, iCell, iAcr, iBias);
            end
        end
        fprintf('  bias %d, ASR %.0f Ohm.cm2 done\n', biasOptions(iBias), acrValues(iAcr));
    end
end
end

function floors = singleWireAreaPower(performance, catalog, ...
        powerCRate, cellWidth_m, cellCounts, biasOptions)
%SINGLEWIREAREAPOWER Floor on cell area, one wire, pack held at its rated power.
%   Every series/parallel wiring of the cells is tried and the kindest kept.
%   Series cells lower the current the rated power represents, P/V, but raise
%   the current the pack's voltage can push through the wire, V/R, and for the
%   thin, resistive wires it is the second that binds.
floors = emptyFloors(height(catalog), numel(cellCounts), 1, numel(biasOptions));
fprintf('\nSingle-wire actuation floor: %d diameters x %d stacks x %d bias.\n', ...
    height(catalog), numel(cellCounts), numel(biasOptions));

for iBias = 1:numel(biasOptions)
    for iCell = 1:numel(cellCounts)
        for iDia = 1:height(catalog)
            overrides = singleWireOverrides(catalog(iDia, :), cellWidth_m, ...
                biasOptions(iBias));
            overrides.battery.driveMode = 'power';
            overrides.battery.powerCRate = powerCRate;
            % Every wiring of the cells is tried: series cells raise the
            % voltage the pack can push through the wire, which is what limits
            % the thinnest, most resistive wires.
            layouts = electricalLayouts(cellCounts(iCell));
            best = missingFloorPoint();
            for iLayout = 1:size(layouts, 1)
                overrides.battery.cellSeriesCount = layouts(iLayout, 1);
                overrides.battery.cellParallelCount = layouts(iLayout, 2);
                best = keepSmallerArea(best, smallestAreaForFullActuation( ...
                    overrides, cellWidth_m, performance));
            end
            floors = storeFloor(floors, best, iDia, iCell, 1, iBias);
        end
    end
    fprintf('  bias %d done\n', biasOptions(iBias));
end
end

function floors = storeFloor(floors, floorPoint, iDia, iCell, iPanel, iBias)
%STOREFLOOR File one bisection result into the sweep arrays.
floors.area_cm2(iDia, iCell, iPanel, iBias) = floorPoint.area_cm2;
floors.deflection_mm(iDia, iCell, iPanel, iBias) = floorPoint.deflection_mm;
floors.ceiling_mm(iDia, iCell, iPanel, iBias) = floorPoint.ceiling_mm;
end

function [areaNeeded_cm2, best_mm, atGridEdge] = areaForBestDeflection(cellAreas_cm2, slab_mm)
%AREAFORBESTDEFLECTION Smallest area that buys essentially all the movement.
%   SLAB_MM holds the deflection over areas down the rows and stack heights
%   across the columns.  Deflection climbs with area and then stops, either
%   because the wires are fully transformed or because the hinge has run out of
%   stroke, so what matters is not the largest area but the first one on the
%   plateau; ninety-nine per cent of the plateau counts as reaching it.
%   ATGRIDEDGE marks the stack heights still climbing at the last area swept,
%   where the answer is a lower bound rather than a requirement.
nCells = size(slab_mm, 2);
areaNeeded_cm2 = nan(1, nCells);
best_mm = nan(1, nCells);
atGridEdge = false(1, nCells);

for iCell = 1:nCells
    column = slab_mm(:, iCell);
    peak_mm = max(column);
    if ~(peak_mm > 0)
        continue
    end
    iFirst = find(column >= 0.99 * peak_mm, 1, 'first');
    areaNeeded_cm2(iCell) = cellAreas_cm2(iFirst);
    best_mm(iCell) = peak_mm;
    atGridEdge(iCell) = iFirst == numel(cellAreas_cm2);
end
end

function plotAreaForMaxDeflection(cellAreas_cm2, cellCounts, bestDeflection_mm, ...
        biasOptions, panelLabels, headline)
%PLOTAREAFORMAXDEFLECTION Footprint a stack needs before more battery stops helping.
%   One figure per panel - one ASR, or the single power case - with one tile per
%   bias option so the two sit side by side.  Y is the footprint, X is the stack
%   height, and the movement bought there is the third dimension: the colour of
%   the marker and the label above it.  A hollow marker means the deflection was
%   still climbing at the largest area swept, so the area shown is a floor.
for iPanel = 1:numel(panelLabels)
    figure('Name', sprintf('Footprint for the best deflection - %s', panelLabels(iPanel)), ...
        'Color', 'w', 'Position', [80 80 1500 620]);
    layout = tiledlayout(1, numel(biasOptions), 'Padding', 'compact', ...
        'TileSpacing', 'compact');
    title(layout, {sprintf(['Minimum stack planform for maximum possible deflection ' ...
        'per number of cells stacked - %s'], panelLabels(iPanel)), headline})

    ax = gobjects(1, numel(biasOptions));
    everyArea_cm2 = [];
    every_mm = [];
    for iBias = 1:numel(biasOptions)
        [areaNeeded_cm2, best_mm, atGridEdge] = areaForBestDeflection(cellAreas_cm2, ...
            squeeze(bestDeflection_mm(:, :, iPanel, iBias)));
        found = ~isnan(areaNeeded_cm2);
        everyArea_cm2 = [everyArea_cm2 areaNeeded_cm2(found)]; %#ok<AGROW>
        every_mm = [every_mm best_mm(found)]; %#ok<AGROW>

        ax(iBias) = nexttile;
        hold on
        plot(cellCounts, areaNeeded_cm2, '-', 'Color', [0.65 0.65 0.65], 'LineWidth', 1.0)
        % Columns, not rows.  Three points passed as a row would be read as one
        % RGB triplet rather than as three values to colour by.
        stacks = cellCounts(:);
        areas = areaNeeded_cm2(:);
        movement_mm = best_mm(:);
        settled = found(:) & ~atGridEdge(:);
        climbing = found(:) & atGridEdge(:);
        scatter(stacks(settled), areas(settled), 120, movement_mm(settled), ...
            'filled', 'MarkerEdgeColor', [0.2 0.2 0.2])
        scatter(stacks(climbing), areas(climbing), 120, movement_mm(climbing), ...
            'LineWidth', 1.6)
        % Labels alternate above and below the markers, so that neighbouring
        % stack heights, which often share a footprint, do not run into each
        % other.  The colour bar carries the unit.
        for iCell = find(found)
            if mod(iCell, 2) == 1
                labelArea_cm2 = areaNeeded_cm2(iCell) * 1.25;
                alignment = 'bottom';
            else
                labelArea_cm2 = areaNeeded_cm2(iCell) / 1.25;
                alignment = 'top';
            end
            text(cellCounts(iCell), labelArea_cm2, sprintf('%.1f', best_mm(iCell)), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', alignment, ...
                'Color', [0.25 0.25 0.25])
        end
        set(gca, 'YScale', 'log')
        grid on
        xticks(cellCounts)
        xlim([min(cellCounts) - 0.5, max(cellCounts) + 0.5])
        xlabel('Cells stacked')
        ylabel('Planform of the stack (cm^2)')
        title(biasLabel(biasOptions(iBias)))
        if ~any(found)
            text(0.5, 0.5, 'nothing moves anywhere on this grid', 'Units', 'normalized', ...
                'HorizontalAlignment', 'center', 'FontAngle', 'italic', ...
                'Color', [0.4 0.4 0.4])
        end
    end

    if isempty(everyArea_cm2)
        continue
    end
    % Both tiles share one area scale and one colour scale, or the bias
    % comparison the figure exists for would be read off two different rulers.
    linkaxes(ax, 'y')
    ylim(ax(1), [0.4 * min(everyArea_cm2), 2.2 * max(everyArea_cm2)])
    for h = ax
        clim(h, colourLimits(every_mm))
    end
    c = colorbar(ax(end));
    c.Layout.Tile = 'east';
    c.Label.String = 'Deflection reached (mm)';
end
end

function label = biasLabel(biasPerActive)
%BIASLABEL How a panel names its bias option, in words rather than a count.
if biasPerActive > 0
    label = 'With bias wires';
else
    label = 'No bias wires';
end
end

function limits = colourLimits(values)
%COLOURLIMITS Colour range for VALUES, kept non-degenerate for clim.
limits = [min(values), max(values)];
if ~(limits(2) > limits(1))
    limits = limits(1) + [0, max(abs(limits(1)), 1) * 0.01];
end
end

function plotAreaForFullActuation(floors, diameters_mm, cellCounts, panelLabels, headline)
%PLOTAREAFORFULLACTUATION Smallest footprint that fully transforms one wire.
%   One tile per panel.  A line is one stack height: more cells put more battery
%   behind the same footprint, so the lines fall as the stack grows.  A missing
%   point is a wire that could not be transformed on any cell up to the search
%   ceiling.
%
%   Bias is not a dimension here.  The bias wires are never heated, so they take
%   no part in reaching temperature and the floor comes out the same with and
%   without them; only the deflection differs, which is the next figure.  That
%   is checked below rather than assumed.
areaNeeded_cm2 = floors.area_cm2;
warnIfSlicesDiffer(areaNeeded_cm2, 4, 'actuation floor', 'the bias options');

colors = parula(numel(cellCounts));

% Panels sit side by side in one row, and the figure is made tall so that the
% four decades of the scale are stretched out: crowded vertically, the ten stack
% heights lie on top of one another.  The axis labels are carried by the layout
% rather than repeated in every panel, which no longer has the width for them.
nPanel = numel(panelLabels);
figure('Name', 'Footprint needed to fully transform one wire', 'Color', 'w', ...
    'Position', [60 60 1500, 800 + 150 * (nPanel > 1)]);
layout = tiledlayout(1, nPanel, 'Padding', 'compact', 'TileSpacing', 'compact');
title(layout, {['Smallest stack planform that brings a single wire to ' ...
    'full transformation'], headline})
if nPanel > 1
    xlabel(layout, 'Wire diameter (mm)')
    ylabel(layout, 'Planform needed (cm^2)')
end

ax = gobjects(1, numel(panelLabels));
for iPanel = 1:numel(panelLabels)
    ax(iPanel) = nexttile;
    hold on
    for iCell = 1:numel(cellCounts)
        plot(diameters_mm, areaNeeded_cm2(:, iCell, iPanel, 1), '-o', ...
            'Color', colors(iCell, :), 'MarkerFaceColor', colors(iCell, :), ...
            'MarkerSize', 4, 'LineWidth', 1.3, ...
            'DisplayName', sprintf('%d cells', cellCounts(iCell)))
    end
    set(gca, 'YScale', 'log')
    grid on
    xlim([0, 1.06 * max(diameters_mm)])
    if nPanel > 1
        % Named by the panel, labelled by the layout, and the y numbers are kept
        % on the leftmost panel only: all four share one scale.  The x ticks are
        % set by hand because a panel this narrow is otherwise left with only
        % its two end values.
        title(panelLabels(iPanel))
        xticks([0 0.25 0.5])
        if iPanel > 1
            set(gca, 'YTickLabel', [])
        end
    else
        xlabel('Wire diameter (mm)')
        ylabel('Planform needed (cm^2)')
    end
    if iPanel == 1
        % In its own column to the right of every tile, clear of the curves.
        lg = legend('Location', 'eastoutside');
        lg.Layout.Tile = 'east';
    end
end

% One scale over every tile, taken from what was actually found: the search
% ceiling is four decades above the floor and would flatten every curve.
found = areaNeeded_cm2(~isnan(areaNeeded_cm2));
if ~isempty(found)
    set(ax(:), 'YLim', [0.6 * min(found), 1.8 * max(found)])
    decadeTicks(ax)
end
end

function decadeTicks(ax)
%DECADETICKS Label every decade of a log axis.
%   On a short axis MATLAB thins its own labels until a range of several
%   decades can be left with one number on it, which is unreadable in print.
for h = ax(:)'
    lim = get(h, 'YLim');
    ticks = 10 .^ (ceil(log10(lim(1))):floor(log10(lim(2))));
    if numel(ticks) >= 2
        set(h, 'YTick', ticks)
    end
end
end

function plotDeflectionAtActuationFloor(floors, diameters_mm, cellCounts, biasOptions, headline)
%PLOTDEFLECTIONATACTUATIONFLOOR What the cheapest working design actually bends.
%   The footprint figure says what it takes to transform one wire.  This says
%   what that buys.  The solid line is the deflection reached on exactly that
%   footprint; the dashed rule in the same colour is the most that hinge could
%   ever give, so the gap between the two is what the thrift costs - and it is
%   the gap, not the curve, that carries the conclusion.
%
%   Only bias is a dimension here.  At the floor the wire is by definition
%   exactly fully transformed, so it delivers exactly its full moment, and what
%   that moment bends is a question about the hinge and the wire alone.  The ASR
%   and the drive mode decide WHERE the floor is, not what standing on it buys,
%   so every ASR panel would be the same picture.  Bias does change it, because
%   the bias wires never heat and so never move the floor, but they do resist
%   the bend.  Both claims are checked below rather than assumed.
warnIfSlicesDiffer(floors.deflection_mm, 3, 'deflection at the actuation floor', ...
    'the ASR panels');
colors = parula(numel(cellCounts));

figure('Name', 'Deflection on the smallest working footprint', 'Color', 'w', ...
    'Position', [60 60 1500 660]);
layout = tiledlayout(1, numel(biasOptions), 'Padding', 'compact', 'TileSpacing', 'compact');
% The caller passes the headline already broken into lines: at the width of a
% page it does not fit on one, and a clipped title is worse than a wrapped one.
% The dashed rules are explained here rather than in a legend box that would sit
% on top of the curves.
title(layout, [cellstr(headline); ...
    {'dashed: the largest deflection each hinge allows, so the gap is what is left unused'}])

ax = gobjects(1, numel(biasOptions));
for iBias = 1:numel(biasOptions)
    ax(iBias) = nexttile;
    hold on
    % The ceiling depends only on how many cells are stacked, so it is one
    % horizontal rule per line rather than a curve of its own.
    ceilings_mm = max(floors.ceiling_mm(:, :, 1, iBias), [], 1, 'omitnan');
    for iCell = 1:numel(cellCounts)
        if ~isnan(ceilings_mm(iCell))
            yline(ceilings_mm(iCell), 'LineStyle', '--', 'Color', colors(iCell, :), ...
                'LineWidth', 0.8, 'HandleVisibility', 'off')
        end
        plot(diameters_mm, floors.deflection_mm(:, iCell, 1, iBias), '-o', ...
            'Color', colors(iCell, :), 'MarkerFaceColor', colors(iCell, :), ...
            'MarkerSize', 4, 'LineWidth', 1.3, ...
            'DisplayName', sprintf('%d cells', cellCounts(iCell)))
    end
    set(gca, 'YScale', 'log')
    grid on
    xlim([0, 1.06 * max(diameters_mm)])
    xlabel('Wire diameter (mm)')
    ylabel('Deflection (mm)')
    title(biasLabel(biasOptions(iBias)))
    if iBias == 1
        % One legend for both tiles, in its own column to the right: on the page
        % a legend inside the axes covers the thin-wire end of the curves.
        lg = legend('Location', 'eastoutside');
        lg.Layout.Tile = 'east';
    end
end

everything = [floors.deflection_mm(:); floors.ceiling_mm(:)];
everything = everything(~isnan(everything) & everything > 0);
if ~isempty(everything)
    set(ax(:), 'YLim', [0.6 * min(everything), 1.8 * max(everything)])
    decadeTicks(ax)
end
end

function printAreaReport(cellAreas_cm2, cellCounts, bestDeflection_mm, bestWireCount, ...
        floors, catalog, panelLabels, biasOptions)
%PRINTAREAREPORT The area figures in numbers, so they can be quoted directly.
rule = repmat('=', 1, 78);
fprintf('\n%s\n AREA REQUIRED  -  footprint of the stack, not the developed cell area\n%s\n', ...
    rule, rule);
fprintf(' Stacked cells share a planform, so one cell''s area is what the wing gives up.\n');

for iPanel = 1:numel(panelLabels)
    for iBias = 1:numel(biasOptions)
        [areaNeeded_cm2, best_mm, atGridEdge] = areaForBestDeflection(cellAreas_cm2, ...
            squeeze(bestDeflection_mm(:, :, iPanel, iBias)));
        fprintf('\n %s, bias %d   (> = still climbing at the largest area swept)\n', ...
            panelLabels(iPanel), biasOptions(iBias));
        fprintf('   cells   footprint (cm2)   deflection (mm)   wires\n');
        for iCell = 1:numel(cellCounts)
            if isnan(areaNeeded_cm2(iCell))
                fprintf('   %5d      nothing moves\n', cellCounts(iCell));
                continue
            end
            iArea = find(cellAreas_cm2 == areaNeeded_cm2(iCell), 1);
            fprintf('   %5d   %s%13.0f   %15.3f   %5d\n', cellCounts(iCell), ...
                blanksOrMark(atGridEdge(iCell)), areaNeeded_cm2(iCell), best_mm(iCell), ...
                bestWireCount(iArea, iCell, iPanel, iBias));
        end
    end
end

fprintf('\n%s\n THE CHEAPEST DESIGN THAT WORKS AT ALL  -  one wire, just fully transformed\n%s\n', ...
    rule, rule);
for iPanel = 1:numel(panelLabels)
    fprintf('\n %s\n   footprint needed (cm2), the same with and without bias wires\n', ...
        panelLabels(iPanel));
    printByDiameter(floors.area_cm2(:, :, iPanel, 1), catalog, cellCounts, '%.0f');
end

% What standing on that floor buys is a question about the hinge and the wire
% alone - the wire is exactly fully transformed there whatever the battery had
% to be - so this half of the table is printed once rather than per panel.
fprintf(['\n Deflection reached on that footprint (mm).  The same for every ASR and\n' ...
    ' for either drive mode: only WHERE the floor sits depends on the battery.\n']);
for iBias = 1:numel(biasOptions)
    fprintf('\n   bias %d\n', biasOptions(iBias));
    printByDiameter(floors.deflection_mm(:, :, 1, iBias), catalog, cellCounts, '%.2f');
    ceilings_mm = max(floors.ceiling_mm(:, :, 1, iBias), [], 1, 'omitnan');
    best_mm = max(floors.deflection_mm(:, :, 1, iBias), [], 1, 'omitnan');
    fprintf('   the best of those against the stroke that hinge allows:\n     cells');
    fprintf('%7d', cellCounts);
    fprintf('\n     mm   ');
    fprintf('%7.1f', ceilings_mm);
    fprintf('\n     used ');
    fprintf('%6.1f%%', 100 * best_mm ./ ceilings_mm);
    fprintf('\n');
end
fprintf('%s\n', rule);
end

function printByDiameter(values, catalog, cellCounts, valueFormat)
%PRINTBYDIAMETER One row per catalogue diameter, one column per stack height.
fprintf('   dia (mm)');
fprintf('%7d', cellCounts);
fprintf('   <- cells stacked\n');
for iDia = 1:height(catalog)
    row = values(iDia, :);
    labels = compose(valueFormat, row);
    labels(isnan(row)) = {'-'};
    fprintf('   %8.3f', catalog.diameter_mm(iDia));
    fprintf('%7s', labels{:});
    fprintf('\n');
end
end

function warnIfSlicesDiffer(values, dim, quantityName, dimensionName)
%WARNIFSLICESDIFFER Guard a figure that draws one slice and claims the rest match.
%   Collapsing a dimension is only honest while the slices along it agree, so
%   the claim is measured on every run rather than taken on trust.
reference = indexAlong(values, dim, 1);
spread = 0;
for k = 2:size(values, dim)
    difference = abs(indexAlong(values, dim, k) - reference) ./ abs(reference);
    spread = max(spread, max(difference, [], 'all', 'omitnan'));
end
if spread > 0.01
    warning(['The %s differs by up to %.1f%% across %s, so drawing one slice of ' ...
        'it is no longer honest.'], quantityName, 100 * spread, dimensionName);
end
end

function slice = indexAlong(values, dim, k)
%INDEXALONG One slice of VALUES taken at position K along dimension DIM.
subscripts = repmat({':'}, 1, ndims(values));
subscripts{dim} = k;
slice = values(subscripts{:});
end

function mark = blanksOrMark(isLowerBound)
%BLANKSORMARK A leading '>' where the tabulated area is only a lower bound.
if isLowerBound
    mark = '>';
else
    mark = ' ';
end
end

function tbl = actuationAreaTable(floors, catalog, cellCounts, biasOptions, ...
        panelName, panelValues)
%ACTUATIONAREATABLE The single-wire floor as one long table, for saving.
[iDia, iCell, iPanel, iBias] = ndgrid(1:height(catalog), 1:numel(cellCounts), ...
    1:numel(panelValues), 1:numel(biasOptions));
tbl = table();
tbl.diameter_mm = reshape(catalog.diameter_mm(iDia), [], 1);
tbl.cellsStacked = reshape(cellCounts(iCell), [], 1);
tbl.(panelName) = reshape(panelValues(iPanel), [], 1);
tbl.biasWiresPerActiveWire = reshape(biasOptions(iBias), [], 1);
tbl.footprintForFullActuation_cm2 = reshape(floors.area_cm2, [], 1);
tbl.deflectionThere_mm = reshape(floors.deflection_mm, [], 1);
tbl.strokeTheHingeAllows_mm = reshape(floors.ceiling_mm, [], 1);
tbl.shareOfStroke_pct = 100 * tbl.deflectionThere_mm ./ tbl.strokeTheHingeAllows_mm;
end
