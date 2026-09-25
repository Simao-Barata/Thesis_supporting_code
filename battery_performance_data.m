function performance = battery_performance_data()
%BATTERY_PERFORMANCE_DATA Structural-battery performance map versus C-rate.
%   Energy and power density are given on a total-mass basis, which is what the
%   model sizes the pack with.  Swap in a different data set by uncommenting it.

performance.cRate = [0.05 0.15 0.5 1.5 3];

% "Advancing Structural Battery Composites: Robust Manufacturing for Enhanced
% and Consistent Multifunctional Performance" - 2023 (commercial LFP + CF, GF separator)
%performance.totalMass.energyDensity_WhPerKg = [41.2 32.1 19.7 12.8 8.7];
%performance.totalMass.powerDensity_WPerKg = [3.85 4.94 8.06 12.4 18.24];

% "A Structural Battery and its Multifunctional Performance" - 2021
% (CF + commercial LFP, GF separator, pouch pressure only)
%   performance.totalMass.energyDensity_WhPerKg = [23.6 14.7 9.1 6.7 4.1];
%   performance.totalMass.powerDensity_WPerKg = [1.65 2.55 4.21 5.71 9.57];
%   Active-material basis of the same cells, for reference:
%   energyDensity_WhPerKg = [106 66.02 40.87 30.10 18.42];
%   powerDensity_WPerKg = [5.98 9.25 15.27 20.70 34.7];

% "A structural battery with carbon fibre electrodes balancing multifunctional
% performance" - 2024 (LFP slurry + CF, ceramic and GF separators)
   performance.totalMass.energyDensity_WhPerKg = [23.7 18.1 13.1 6.6 4.3];
   performance.totalMass.powerDensity_WPerKg = [1.2 2.6 6.2 10.2 13.2];
end
