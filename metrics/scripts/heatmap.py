#!/usr/bin/env python3
# Copyright (c) 2020 Performance Portability authors
# SPDX-License-Identifier: MIT

import argparse
import csv
import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.axes_grid1 import make_axes_locatable

# Argument parsing
parser = argparse.ArgumentParser()
parser.add_argument("input", help="CSV input file")
parser.add_argument("output", help="PDF output file")
parser.add_argument(
    "--higher-is-better",
    help="High numbers are better than low number (e.g. when plotting bandwidth)",
    action="store_true")
parser.add_argument(
    "--factorize",
    help="Divide all input results by this number",
    action="store",
    type=float,
    default=1.0)
parser.add_argument(
    "--percent",
    help="Input is in percent",
    action="store_true")
parser.add_argument(
    "--mean",
    help="Plot the mean and standard deviation against each column",
    action="store_true")
args = parser.parse_args()

# Open the input .csv file
data = csv.DictReader(open(args.input))

# Get the list of headings from first row
headings = data.fieldnames[1:]
if len(headings) < 1:
    raise Exception("No input fields found")

# Name of the series, what the rows in the CSV actually are
series_key = data.fieldnames[0]


series = []  # a row in the input file

heatmap = []  # empty, to be populated by reading the input file
labels = []  # labels to display in each heatmap entry

plt.rc('text', usetex=True)
plt.rc('font', family='serif', serif='Times')
fig, ax = plt.subplots()

max_all = -np.inf
min_all = np.inf

for result in data:
    def get(name):
        str = result[name]
        try:
            return float(str)
        except BaseException:
            return str

    def eff(a, b):
        if isinstance(a, float) and isinstance(b, float):
            return float(100.0 * (a / b))
        elif a == '-' or b == '-':
            return float(-100.0)
        else:
            return float(0.0)

    raw = [get(h) for h in headings]

    # Skip over applications without any results
    if not any([isinstance(x, float) for x in raw]):
        continue

    series.append(result[series_key])
    heatmap.append([r if isinstance(r, float) else float('nan') for r in raw])
    max_all = max(max_all, max(heatmap[len(heatmap)-1]))
    min_all = min(min_all, min(heatmap[len(heatmap)-1]))

    l = []
    for i in range(len(raw)):
        if not isinstance(raw[i], float):
            l.append('-')
        else:
            if args.percent:
                if plt.rcParams['text.usetex']:
                    if raw[i] / args.factorize < 100.0:
                        l.append('%.1f\\%%' % (raw[i] / args.factorize))
                    else:
                        l.append('%.0f\\%%' % (raw[i] / args.factorize))
                else:
                    if raw[i] / args.factorize < 100.0:
                        l.append('%.1f%%' % (raw[i] / args.factorize))
                    else:
                        l.append('%.0f%%' % (raw[i] / args.factorize))
            else:
                if not raw[i].is_integer():
                    l.append('%.1f' % (raw[i] / args.factorize))
                else:
                    l.append('%.0f' % (raw[i] / args.factorize))
    labels.append(l)

# Set color map to match blackbody, growing brighter for higher values
fig.set_figwidth(fig.get_figwidth() / 5 * len(l))
colors = "viridis"
if not args.higher_is_better:
    colors = colors + "_r"
cmap = plt.get_cmap(colors)
x = np.arange(len(l)+1)
y = np.arange(len(heatmap)+1)
masked = np.ma.masked_where(np.isnan(heatmap),heatmap)
cmesh = plt.pcolormesh(
    x,
    y,
    masked,
    cmap=cmap,
    edgecolors='k',
    vmin=1.0E-6)
ax.set_yticks(np.arange(len(heatmap)) + 0.5, minor=False)
ax.set_xticks(np.arange(len(heatmap[0])) + 0.5, minor=False)
ax.set_yticklabels(series, fontsize='xx-large')
for i in range(len(headings)):
  headings[i] = headings[i].replace('_', '\_')
ax.set_xticklabels(headings, fontsize='xx-large', rotation=45)
plt.gca().invert_yaxis()

# Add colorbar
plt.colorbar(cmesh)

#one_third = min_all + (max_all - min_all) / 3.0
#two_thirds = min_all + 2.0 * (max_all - min_all) / 3.0
one_third = max_all / 3.0
two_thirds = 2.0 * max_all / 3.0

# Add labels
for i in range(len(headings)):
    for j in range(len(series)):
        labelcolor = 'black'
        if args.higher_is_better and heatmap[j][i] < one_third: 
            labelcolor='white'
        elif not args.higher_is_better and heatmap[j][i] > two_thirds: 
            labelcolor='white'
        plt.text(i + 0.5, j + 0.55, labels[j][i],
                 ha='center', va='center', color=labelcolor, weight='bold', size='xx-large')

plt.savefig(args.output, bbox_inches='tight')
