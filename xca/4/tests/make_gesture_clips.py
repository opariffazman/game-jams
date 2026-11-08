#!/usr/bin/env python3
"""Renders fake-camera clips: a hand photo moving along a scripted path on a grey 640x480 background at 15 fps."""
import subprocess, sys
from PIL import Image

FPS = 15
W, H = 640, 480
hand = Image.open('/tmp/hands/pointing_up.jpg').convert('RGB')
hand = hand.resize((250, int(250 * hand.height / hand.width)))
bg = Image.new('RGB', (W, H), (135, 135, 135))

def smooth(a, b, t0, dur):
    def f(t):
        if t <= t0: return a
        if t >= t0 + dur: return b
        k = (t - t0) / dur
        return a + (b - a) * (3 * k * k - 2 * k * k * k)
    return f

def seq(*parts):
    """Each part is (t_end, fn). The path uses the first part whose t_end exceeds t."""
    def f(t):
        for end, fn in parts:
            if t < end: return fn(t)
        return parts[-1][1](t)
    return f

def render(name, xf, yf, seconds):
    cmd = ['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
           '-pix_fmt', 'yuv420p', f'/tmp/gest/{name}.y4m']
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(int(seconds * FPS)):
        t = i / FPS
        frame = bg.copy()
        frame.paste(hand, (int(xf(t)), int(yf(t))))
        p.stdin.write(frame.tobytes())
    p.stdin.close(); p.wait()

X0, Y0 = 200, 100
const = lambda v: (lambda t: v)
# Rest: hand still with tiny sway. 20 s.
render('rest', lambda t: X0, lambda t: Y0, 20)
# Slow drift: right in 3 s, left back in 3 s, loops cleanly.
render('drift', seq((3, smooth(X0, X0 + 220, 0, 3)), (8, lambda t: X0 + 220), (11, smooth(X0 + 220, X0, 8, 3)), (14, lambda t: X0)), const(Y0), 14)
# Flick right x4 (0.25 s out), slow return (1.2 s), 3 s apart. Ends at start.
def flicks(dx, dy, name, n=4):
    period = 3.0
    xs, ys = [], []
    parts_x, parts_y = [], []
    for k in range(n):
        t0 = 1.0 + k * period
        parts_x.append((t0 + 0.0, lambda t: None))
    def pos(t, axis):
        d = dx if axis == 'x' else dy
        base = X0 if axis == 'x' else Y0
        # shift start so the flick stays inside the frame
        start = base - d / 2
        val = start
        for k in range(n):
            t0 = 1.0 + k * period
            if t < t0: break
            if t < t0 + 0.25: val = smooth(start, start + d, t0, 0.25)(t); break
            if t < t0 + 0.6: val = start + d; break
            if t < t0 + 1.8: val = smooth(start + d, start, t0 + 0.6, 1.2)(t); break
            val = start
        return val
    render(name, lambda t: pos(t, 'x'), lambda t: pos(t, 'y'), 1.0 + n * period + 1.0)
# The preview is mirrored, so a player flick to the right moves the hand left in the raw camera image.
flicks(-240, 0, 'flick_r')
flicks(240, 0, 'flick_l')
flicks(0, 170, 'flick_d')
flicks(0, -170, 'flick_u')
# Mixed: right, then left, alternating with a quick return of 0.5 s. Probes the return stroke.
def quick_return(name):
    n = 4
    period = 3.0
    start = X0 + 120
    def pos(t):
        val = start
        for k in range(n):
            t0 = 1.0 + k * period
            if t < t0: break
            if t < t0 + 0.25: val = smooth(start, start - 240, t0, 0.25)(t); break
            if t < t0 + 0.5: val = start - 240; break
            if t < t0 + 1.0: val = smooth(start - 240, start, t0 + 0.5, 0.5)(t); break
            val = start
        return val
    render(name, pos, const(Y0), 1.0 + n * period + 1.0)
quick_return('flick_r_quick_return')
# Walk: hand repositions at a normal pace by 120 px in 0.5 s, 4 times, back and forth.
render('walk', seq((2, const(X0)), (2.5, smooth(X0, X0 + 120, 2, 0.5)), (5, lambda t: X0 + 120), (5.5, smooth(X0 + 120, X0, 5, 0.5)), (8, lambda t: X0)), const(Y0), 8)
