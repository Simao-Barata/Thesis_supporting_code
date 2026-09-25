function catalog = load_wire_catalog(fileName)
%LOAD_WIRE_CATALOG Read the SMA wire catalog into a table the studies can use.
%   Extra columns in the file are ignored.

if nargin < 1
    fileName = 'sma_wire_catalog.csv';
end

raw = readtable(fileName);
catalog = table();
catalog.diameter_mm = raw.diameter_mm;
catalog.diameter_m = raw.diameter_mm * 1e-3;
catalog.resistancePerMeter_OhmPerM = raw.resistance_ohm_per_m;
catalog.pullForce_N = raw.pull_force_at_70c_n;
catalog.referenceCurrent_A = raw.referencecurrent1scontraction_a;
end
