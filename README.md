# SMA-actuated morphing hinge powered by a structural battery

A reduced-order multiphysics model of a morphing trailing-edge hinge actuated by
shape-memory-alloy (SMA) wires and powered by a structural battery. It couples
what the battery can deliver to the electro-thermal heating of the wires, and
that to the bending of the hinge, and reports the tip deflection.

The model was written for an MSc thesis at TU Delft. It answers one question:
how little battery can a design carry and still actuate?

## What it does

The hinge is a polymer wedge outboard of the battery stack, thick at the root
and tapering to a thin tip, with SMA wires embedded just inside the surface and
anchored at both ends. Heating the wires contracts them, and because they are
anchored above the neutral axis, the wedge bends upwards. The battery is both
the power source and the rigid root.

One run follows four steps:

1. the pack and the hinge section are described from the design inputs;
2. the circuit and a three-node thermal network (wire, polymer sleeve, bulk) are
   marched through the actuation window, giving the wire temperature history;
3. that history gives how far the wires have transformed, and so the moment they
   apply;
4. the hinge is integrated along its span, exactly in rotation, to a tip
   deflection.

The pack can drive the wires in two ways, which is what the two studies use:

- **power** — the delivered power is read from a measured performance map at a
  nominated C-rate, as a cell does under sustained discharge;
- **resistance** — the pack is an EMF behind its own internal resistance, set by
  the area-specific resistance of the cell, and Ohm's law decides the current.

## Requirements

MATLAB R2024b or later. Base MATLAB only: no toolboxes are needed.

## Running it

Put every file in one folder and set that folder as the working directory.

### One actuation of a single design

```matlab
run_morphing_case
```

Edit the design in `build_morphing_inputs.m`, in the block marked
`USER SETTINGS`, then run this. It prints the headline numbers and draws the
time history and a side view of the geometry.

### The parametric studies

```matlab
minimal_requirements_study
```

This sweeps the design space and answers the feasibility question. The settings
at the top of the file choose which study runs:

```matlab
driveMode = 'resistance';   % or 'power'
```

- `'power'` — **Study 1**: the pack delivers what the performance map gives at
  `powerCRate`, which sizes the battery for sustained operation.
- `'resistance'` — **Study 2**: the pack is described by its area-specific
  resistance, swept over `areaResistanceProducts_Ohmcm2`, which sizes it for a
  single short actuation.

Run it once in each mode to reproduce both studies. Each run takes on the order
of ten to thirty minutes, sweeps tens of thousands of designs, writes its
results as CSV files in the working directory, and draws its figures.

## The files

| File | What it is |
| --- | --- |
| `run_morphing_case.m` | one actuation of the baseline design |
| `minimal_requirements_study.m` | the two parametric studies |
| `build_morphing_inputs.m` | every user setting, and the only place geometry is derived |
| `simulate_morphing_wing.m` | the model itself: circuit, thermal network, structure |
| `battery_performance_data.m` | energy and power density of the cell against C-rate |
| `load_wire_catalog.m` | reads the wire catalogue |
| `sma_wire_catalog.csv` | the SMA wires: resistance, pull force, contraction current |
| `save_table.m` | writes a results table to CSV |
| `style_figures.m` | one text style for every figure, sized for printing |

Geometry is derived in `build_morphing_inputs.m` and nowhere else. A study
changes a design by passing an overrides struct to it:

```matlab
o.sma.wireDiameter_m = 0.15e-3;
o.battery.cellParallelCount = 12;
inputs = build_morphing_inputs(o);
```

The hinge thickness, the moment arm, the wire length, the pack resistance and
the thermal network all follow from the settings and must not be set by hand.

## What the model does not do

It is a reduced-order model for preliminary design, not a substitute for
high-fidelity analysis. It leaves out aerodynamic loading, SMA hysteresis and
latent heat, distributed temperature fields, laminate theory, and any cooling
path other than conduction into the hinge, so it describes a single stroke
rather than a duty cycle. The hinge is treated as a beam, and the wires are
assumed to slide freely between their anchors. The assumptions and their
consequences are set out in the thesis.

## Licence

MIT. See `LICENSE`.
