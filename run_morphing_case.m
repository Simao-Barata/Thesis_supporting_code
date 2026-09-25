% RUN_MORPHING_CASE  One actuation run of the baseline design.
%   Edit the design in build_morphing_inputs.m, then run this file.

clear; clc; close all;

inputs = build_morphing_inputs();          % the design, editable there
performance = battery_performance_data();  % the cell's energy and power vs C-rate

results = simulate_morphing_wing(inputs, performance);

disp(results.summary)

style_figures();
