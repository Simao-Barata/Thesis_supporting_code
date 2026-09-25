function inputs = build_morphing_inputs(overrides)
%BUILD_MORPHING_INPUTS Sizing parameters, and the only place geometry is derived.
%
%   inputs = BUILD_MORPHING_INPUTS() returns the baseline design.
%
%   inputs = BUILD_MORPHING_INPUTS(overrides) applies a struct that mirrors the
%   inputs layout before every derived quantity is recomputed, e.g.
%       o.sma.wireDiameter_m = 0.15e-3;
%       o.battery.cellParallelCount = 12;
%       inputs = build_morphing_inputs(o);
%
%   Studies must change the design this way.  No other file derives hinge
%   geometry, wire geometry or the thermal network.
%
%   Units are SI unless the field name says otherwise.

% =====================================================================
%  USER SETTINGS.  Everything below this banner is a free choice; nothing
%  else in the project is.  The section after it derives the geometry, the
%  circuit and the thermal network from these values, and those derived
%  fields must not be set by hand.
% =====================================================================

%% Battery: the cell, and how the cells are wired
% Two voltages, because the two drive modes need different ones.
%   nominalVoltage_V     what one cell holds AT ITS TERMINALS while it is being
%                        discharged at the rated C-rate.  This is the voltage
%                        the performance map belongs to, so it is the one the
%                        power mode divides the rated power by.  Held constant
%                        across the map: power density over energy density
%                        returns the C-rate at every point, and the voltage
%                        cancels in P = V*I = C*(V*Q) = C*E.
%   openCircuitVoltage_V what one cell holds with no current drawn.  This is the
%                        EMF that drives the current in the resistance mode,
%                        where the drop across the internal resistance is
%                        computed rather than assumed.
inputs.battery.nominalVoltage_V = 2.8;                  % at the terminals at 1.5C
inputs.battery.openCircuitVoltage_V = 3.3;              % LFP against carbon fibre
% How the stacked cells are wired.  Total cells = series * parallel, and that
% total is what sets the stack thickness, so the wiring is a free choice at
% fixed geometry.
inputs.battery.cellSeriesCount = 1;                     % cells in series in a string
inputs.battery.cellParallelCount = 6;                   % such strings in parallel
% How the pack is allowed to drive the wires.
%   'resistance' models it as an EMF behind its own internal resistance, so the
%                current follows from Ohm's law and the ASR decides everything.
%   'power'      takes the delivered power straight from the performance map at
%                powerCRate.  That measurement already contains the internal
%                loss, so the pack resistance drops out of the circuit and the
%                ASR ceases to matter.
inputs.battery.driveMode = 'resistance';
inputs.battery.powerCRate = 1.5;                        % 'power' mode only: the rate the map is read at
inputs.battery.areaResistanceProduct_Ohmcm2 = 2000;     % ASR -> internal resistance of one cell
inputs.battery.operatingCRate = 3;                      % 'resistance' mode only: starting guess for the self-consistent C-rate solve
inputs.battery.reserveEnergyFraction = 0.05;            % share of the energy held back, never drawn

%% Battery: geometry and mass
inputs.battery.width_m = 0.03;                          % also the width of the hinge
inputs.battery.length_m = 0.3;                          % chordwise length; width x length = planform of one cell
inputs.battery.cellThickness_m = 1.0e-3;                % one cell; the stack is this times the cell count
inputs.battery.compositeArealDensity_kgpm2 = 0.35;      % mass per unit electrode area of the laminate

%% Polymer hinge: the part that bends
inputs.polymer.hingeLength_m = 0.05;                    % the deflecting span, outboard of the battery
inputs.polymer.maxTipRotation_deg = 90;                 % actuation stops here (pre-strain, end stop or controller)
inputs.polymer.outerCoatingThickness_m = 0.5e-3;        % polymer over the wires on each face
inputs.polymer.sideProfile = 'triangular';              % 'triangular' tapers to the tip, 'rectangular' does not
inputs.polymer.modulus_Pa = 0.01e9;                     % Young's modulus of the hinge polymer
inputs.polymer.density_kgm3 = 970;

%% SMA wires
% The wire length is not a free parameter: it follows the hinge geometry above.
inputs.sma.seriesWires = 1;                             % wires in series along a branch
inputs.sma.parallelBranches = 1;                        % such branches in parallel
inputs.sma.wireDiameter_m = 0.1e-3;
inputs.sma.resistancePerMeter_OhmPerM = 126;            % 0.1 mm wire, sma_wire_catalog.csv
inputs.sma.resistanceTempCoeff_1pK = 4e-4;              % relative resistance change per K
inputs.sma.transformationStress_Pa = 170e6;             % plateau stress, used when no catalogue force is given
inputs.sma.pullForcePerWire_N = NaN;                    % NaN -> transformationStress * wire area
inputs.sma.recoverableStrain = 0.05;                    % stroke: how far a wire can contract
% Unheated wires mirrored on the far side of the neutral axis, for two-way
% actuation.  0 leaves the polymer alone to return the section.  They stay
% martensitic, so they resist bending while the active wires do not.
inputs.sma.biasWiresPerActiveWire = 1;
inputs.sma.youngModulusMartensite_Pa = 28e9;            % stiffness of the bias wires
inputs.sma.density_kgm3 = 6450;
inputs.sma.specificHeat_JpkgK = 837;
inputs.sma.activationStart_C = 75;                      % read off the heating strain-temperature curve
inputs.sma.activationFinish_C = 90;                     % where the recovered strain approaches 5%
inputs.sma.maxWireTemperature_C = 300;                  % above this a design counts as failed
inputs.sma.referenceTemperature_C = 20;                 % where the catalogue resistance is quoted

%% Thermal environment: conduction into the surrounding polymer only.
% No convection and no radiation.  Heat leaves the wire only by conducting into
% the polymer it is embedded in.
inputs.thermal.ambientTemperature_C = 20;
inputs.thermal.heatingEfficiency = 0.9;                 % share of the dissipated power that heats the wire
inputs.thermal.polymerConductivity_WpmK = 0.15;
inputs.thermal.polymerSpecificHeat_JpkgK = 1460;
inputs.thermal.wireInterfaceResistancePerWire_KpW = 0;  % extra wire/polymer contact resistance, 0 = perfect contact

%% Time integration and actuation schedule
inputs.simulation.dt_s = 0.05;                          % time step
inputs.simulation.totalTime_s = 120;                    % how long the run is followed, cooling included
inputs.simulation.actuationStart_s = 0;                 % current on
inputs.simulation.actuationStop_s = 30;                 % current off: one actuation stroke
inputs.simulation.plotResults = true;                   % false for sweeps, which draw their own figures

% =====================================================================
%  END OF USER SETTINGS.
% =====================================================================

if nargin > 0 && ~isempty(overrides)
    inputs = mergeStruct(inputs, overrides);
end
inputs = deriveDesign(inputs);
end

function inputs = deriveDesign(inputs)
% DERIVE DESIGN Everything that follows from the primary values above.

%% Battery geometry and internal resistance
inputs.battery.planformArea_m2 = inputs.battery.width_m * inputs.battery.length_m;
inputs.battery.cellCount = inputs.battery.cellSeriesCount * inputs.battery.cellParallelCount;
inputs.battery.totalThickness_m = inputs.battery.cellCount * inputs.battery.cellThickness_m;
inputs.battery.internalResistancePerCell_Ohm = ...
    inputs.battery.areaResistanceProduct_Ohmcm2 / (1e4 * inputs.battery.planformArea_m2);
% Thevenin equivalent of the pack.  A string of cellSeriesCount cells adds both
% EMF and internal resistance; putting cellParallelCount such strings side by
% side leaves the EMF alone and divides the resistance.  Which single-cell
% voltage goes into it depends on how the pack is driven: the power mode reads
% its power from a map measured at the terminals under load, so it must use the
% loaded voltage, while the resistance mode drives the current from the EMF and
% works the loaded voltage out for itself.
if strcmpi(inputs.battery.driveMode, 'power')
    cellVoltage_V = inputs.battery.nominalVoltage_V;
else
    cellVoltage_V = inputs.battery.openCircuitVoltage_V;
end
inputs.battery.packVoltage_V = inputs.battery.cellSeriesCount * cellVoltage_V;
inputs.battery.packResistance_Ohm = inputs.battery.cellSeriesCount * ...
    inputs.battery.internalResistancePerCell_Ohm / inputs.battery.cellParallelCount;

%% Hinge geometry, and the wire line inside it
inputs.polymer.width_m = inputs.battery.width_m;
inputs.polymer.thickness_m = inputs.battery.totalThickness_m + ...
    2 * inputs.polymer.outerCoatingThickness_m;
% The wire is embedded just inside the outer coating, so at the root it sits
% half the hinge thickness less that coating from the neutral axis.
inputs.polymer.wireRootOffset_m = max(0.5 * inputs.polymer.thickness_m - ...
    inputs.polymer.outerCoatingThickness_m, 0);

% Stations along the hinge, from the root (0) to the tip (1), at which the
% section is described.  A tapered hinge thins linearly to a tip of two coatings
% back to back: the thinnest section that still contains the wire, which
% therefore meets the neutral axis exactly at the tip.
inputs.polymer.spanStation = linspace(0, 1, 201);
switch lower(string(inputs.polymer.sideProfile))
    case "triangular"
        tipThickness_m = 2 * inputs.polymer.outerCoatingThickness_m;
        % The wire is the hypotenuse of the triangle whose legs are the hinge
        % length and that offset: it runs from the root out to the tip.
        inputs.polymer.wireLength_m = hypot(inputs.polymer.hingeLength_m, ...
            inputs.polymer.wireRootOffset_m);
        armShape = 1 - inputs.polymer.spanStation;
    case "rectangular"
        tipThickness_m = inputs.polymer.thickness_m;
        inputs.polymer.wireLength_m = inputs.polymer.hingeLength_m;
        armShape = ones(size(inputs.polymer.spanStation));
    otherwise
        error('Unknown polymer sideProfile "%s".', inputs.polymer.sideProfile);
end
inputs.polymer.thicknessAlongSpan_m = inputs.polymer.thickness_m + ...
    (tipThickness_m - inputs.polymer.thickness_m) * inputs.polymer.spanStation;
% The wire is a chord, not a line parallel to the neutral axis, so its lever is
% the perpendicular distance from the axis to that chord.  Geometrically this is
% the root offset foreshortened by the cosine of the wire's inclination,
% cos(a) = hingeLength / wireLength.  For a rectangular hinge the wire does run
% parallel and the two coincide.  The distinction is worth 0.5% at six cells but
% 12% at thirty, where the wire is inclined by 27 degrees.  Along a tapered hinge
% the lever then falls with the wire's height, to nothing at the tip.
inputs.polymer.wireMomentArm_m = inputs.polymer.wireRootOffset_m * ...
    inputs.polymer.hingeLength_m / inputs.polymer.wireLength_m;
inputs.polymer.wireArmAlongSpan_m = inputs.polymer.wireMomentArm_m * armShape;
hingeVolume_m3 = 0.5 * (inputs.polymer.thickness_m + tipThickness_m) * ...
    inputs.polymer.hingeLength_m * inputs.polymer.width_m;

%% SMA wire set.  Heated wires on the active side, optionally mirrored by
%% unheated bias wires that resist bending and help return the section.
inputs.sma.wireCount = inputs.sma.seriesWires * inputs.sma.parallelBranches;
inputs.sma.biasWireCount = inputs.sma.wireCount * inputs.sma.biasWiresPerActiveWire;
inputs.sma.wireArea_m2 = pi * inputs.sma.wireDiameter_m^2 / 4;
if ~isfinite(inputs.sma.pullForcePerWire_N)
    inputs.sma.pullForcePerWire_N = inputs.sma.transformationStress_Pa * ...
        inputs.sma.wireArea_m2;
end
% Wires in series add their resistance along a branch; parallel branches divide
% the result again.  With wireCount = seriesWires * parallelBranches fixed, the
% layout trades resistance against current without changing the pull force.
inputs.sma.circuitResistance_Ohm = max(inputs.sma.resistancePerMeter_OhmPerM * ...
    inputs.polymer.wireLength_m * inputs.sma.seriesWires / inputs.sma.parallelBranches, eps);

%% Thermal network: heated wires -> a sleeve of polymer -> the rest of the hinge
%   Heat leaves a wire radially, and the temperature it produces falls steeply
%   close to the wire and gently far away.  A single lumped polymer node cannot
%   hold that shape and comes out badly too hot, so the polymer is split into a
%   sleeve immediately around each wire and the bulk beyond it.  The dividing
%   radius is the geometric mean of the wire and outer radii, which is the
%   midpoint of a logarithmic profile.
wireRadius_m = 0.5 * inputs.sma.wireDiameter_m;
heatedWireVolume_m3 = inputs.sma.wireCount * inputs.sma.wireArea_m2 * ...
    inputs.polymer.wireLength_m;
% Bias wires displace polymer too, but only the active ones are heated.
polymerVolume_m3 = max(hingeVolume_m3 - heatedWireVolume_m3 * ...
    (1 + inputs.sma.biasWiresPerActiveWire), 0);
inputs.thermal.wireThermalMass_JpK = max(heatedWireVolume_m3 * ...
    inputs.sma.density_kgm3 * inputs.sma.specificHeat_JpkgK, eps);

% Each heated wire warms a half-cylinder of polymer, the cylinders sized so that
% together they fill the hinge.
outerRadius_m = sqrt(wireRadius_m^2 + 2 * polymerVolume_m3 / ...
    (pi * inputs.sma.wireCount * inputs.polymer.wireLength_m));
sleeveRadius_m = sqrt(wireRadius_m * outerRadius_m);

% Split the polymer heat capacity between the two by the volume each holds.
polymerThermalMass_JpK = polymerVolume_m3 * inputs.polymer.density_kgm3 * ...
    inputs.thermal.polymerSpecificHeat_JpkgK;
sleeveShare = (sleeveRadius_m^2 - wireRadius_m^2) / ...
    max(outerRadius_m^2 - wireRadius_m^2, eps);
inputs.thermal.sleeveThermalMass_JpK = polymerThermalMass_JpK * sleeveShare;
inputs.thermal.bulkThermalMass_JpK = polymerThermalMass_JpK * (1 - sleeveShare);

% Each node represents its shell at the shell's own geometric mean radius, so
% the conduction resistances run from the wire surface to the sleeve centre, and
% from there to the bulk centre.  Taking the resistance out to the far edge
% instead, as a single-node model must, understates how fast heat escapes.
sleeveCentre_m = sqrt(wireRadius_m * sleeveRadius_m);
bulkCentre_m = sqrt(sleeveRadius_m * outerRadius_m);
conductanceScale = inputs.sma.wireCount * pi * ...
    inputs.thermal.polymerConductivity_WpmK * inputs.polymer.wireLength_m;
if polymerThermalMass_JpK > 0
    interfaceConductance_WpK = inf;
    if inputs.thermal.wireInterfaceResistancePerWire_KpW > 0
        interfaceConductance_WpK = inputs.sma.wireCount / ...
            inputs.thermal.wireInterfaceResistancePerWire_KpW;
    end
    spreadConductance_WpK = conductanceScale / log(sleeveCentre_m / wireRadius_m);
    inputs.thermal.wireToSleeveConductance_WpK = 1 / ...
        (1 / spreadConductance_WpK + 1 / interfaceConductance_WpK);
    inputs.thermal.sleeveToBulkConductance_WpK = ...
        conductanceScale / log(bulkCentre_m / sleeveCentre_m);
else
    inputs.thermal.wireToSleeveConductance_WpK = 0;   % nothing to conduct into
    inputs.thermal.sleeveToBulkConductance_WpK = 0;
end
end

function base = mergeStruct(base, updates)
%MERGESTRUCT Recursively overwrite fields of BASE with those of UPDATES.
names = fieldnames(updates);
for i = 1:numel(names)
    name = names{i};
    if isstruct(updates.(name)) && isfield(base, name) && isstruct(base.(name))
        base.(name) = mergeStruct(base.(name), updates.(name));
    else
        base.(name) = updates.(name);
    end
end
end
