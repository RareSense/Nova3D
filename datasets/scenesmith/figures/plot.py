"""Reproducible figures from the released 20-pair declaration inspection."""
from pathlib import Path
import csv
import json
import shutil

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator
import numpy as np

import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--csv', type=Path, default=Path(__file__).with_name('plot-data.csv'))
parser.add_argument('--output', type=Path, default=Path('figures'))
args = parser.parse_args()
FIG = args.output
FIG.mkdir(parents=True, exist_ok=True)
rows = list(csv.DictReader((args.csv).open()))
assert len(rows) == 20 and len({r['scene_id'] for r in rows}) == 20
ss = np.array([int(r['scenesmith_mjcf_scalar_joints']) for r in rows])
nova = np.array([int(r['nova_mjcf_scalar_joints']) for r in rows])
assert (ss.sum(), nova.sum(), (ss > 0).sum(), (nova > 0).sum()) == (87, 93, 11, 18)
blue, orange, ink, muted = '#176B87', '#C46B24', '#192B3A', '#566575'
plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 11,
                     'text.color': ink, 'axes.labelcolor': ink,
                     'xtick.color': muted, 'ytick.color': ink,
                     'axes.spines.top': False, 'axes.spines.right': False,
                     'axes.spines.left': False, 'axes.spines.bottom': False,
                     'savefig.facecolor': 'white'})

fig, ax = plt.subplots(figsize=(10, 3.7))
fig.subplots_adjust(left=.15, right=.93, top=.72, bottom=.23)
fig.text(.04, .91, 'Articulation coverage across the 20 matched scenes', fontsize=18, weight='bold')
fig.text(.04, .81, 'Scenes containing at least one declared hinge or slide joint', fontsize=11, color=muted)
values = [11, 18]
ax.barh([1, 0], [20, 20], color='#EDF1F4', height=.48)
ax.barh([1, 0], values, color=[orange, blue], height=.48)
ax.set_yticks([1, 0], ['SceneSmith', 'Nova3D'])
ax.set_xlim(0, 20); ax.set_xticks([0, 5, 10, 15, 20]); ax.tick_params(length=0)
for y, v in zip([1, 0], values):
    ax.text(v - .35, y, f'{v}/20  ({v/20:.0%})', color='white', ha='right', va='center', weight='bold')
ax.set_xlabel('Number of scenes', labelpad=8)
fig.text(.04, .035, 'Declared articulation coverage; not a mechanism-success or prompt-adherence score.', fontsize=10, color=muted)
for ext in ['png', 'svg', 'pdf']:
    fig.savefig(FIG / f'articulation-coverage.{ext}', dpi=180)
plt.close(fig)

fig, ax = plt.subplots(figsize=(11.7, 9.7))
fig.subplots_adjust(left=.39, right=.95, top=.84, bottom=.1)
fig.text(.035, .95, 'Articulated joints in each matched scene', fontsize=19, weight='bold')
fig.text(.035, .91, 'Same prompt and scene ID; independently generated environments', fontsize=11, color=muted)
y = np.arange(len(rows))
ax.hlines(y, np.minimum(ss, nova), np.maximum(ss, nova), color='#CAD3DA', linewidth=2.5, zorder=1)
ax.scatter(ss, y, color=orange, s=65, marker='s', label='SceneSmith', zorder=3)
ax.scatter(nova, y, color=blue, s=65, marker='o', label='Nova3D', zorder=4)
for i, (a, b) in enumerate(zip(ss, nova)):
    if a == b:
        ax.annotate(str(a), (a, i), xytext=(9, 0), textcoords='offset points', va='center', fontsize=9)
    else:
        for v, color, offset in [(a, orange, -9 if a < b else 9), (b, blue, -9 if b < a else 9)]:
            ax.annotate(str(v), (v, i), xytext=(offset, 0), textcoords='offset points', va='center',
                        ha='right' if offset < 0 else 'left', color=color, fontsize=9, weight='bold')
ax.set_yticks(y, [f'{r["scene_id"]}  ·  {r["environment"]}' for r in rows], fontsize=9)
ax.invert_yaxis(); ax.set_xlim(-1, 20)
ax.set_xticks([0, 5, 10, 15, 20]); ax.tick_params(length=0)
ax.grid(axis='x', color='#E6EBEF'); ax.set_axisbelow(True)
ax.set_xlabel('Declared hinge / slide joints', labelpad=9)
ax.legend(loc='lower right', bbox_to_anchor=(1, 1.015), ncol=2, frameon=False)
fig.text(.035, .025, 'All 20 selected scenes are shown. More joints does not establish more correct or functional mechanisms.',
         fontsize=10, color=muted)
for ext in ['png', 'svg', 'pdf']:
    fig.savefig(FIG / f'paired-joint-counts.{ext}', dpi=180)
plt.close(fig)
shutil.copyfile(args.csv, FIG / 'plot-data.csv')
(FIG / 'figure-metadata.json').write_text(json.dumps({
    'scene_count': 20, 'metric': 'Declared scalar hinge/slide joints; fixed and free joints excluded',
    'source': '../paired-scenes.csv', 'scenesmith_scenes_with_joints': 11,
    'nova_scenes_with_joints': 18, 'difference_percentage_points': 35,
    'nova_more_joint_scenes': int((nova > ss).sum()), 'equal_joint_scenes': int((nova == ss).sum()),
    'nova_fewer_joint_scenes': int((nova < ss).sum()),
    'scope': 'Descriptive results for the selected pairs; no task-success or superiority estimate.'
}, indent=2) + '\n')
print('Created PNG, SVG, PDF figures and data.')
