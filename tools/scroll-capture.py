#!/usr/bin/env python3
"""Scrolling screenshot capture for Caelestia area picker.

Auto mode: script scrolls the window, grabs frames, stitches.
Manual mode: you scroll, script watches for motion and grabs frames.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import time
import signal
import shutil

import numpy as np
from PIL import Image

STILL_THRESHOLD = 1.2
OVERLAP_THRESHOLD = 5.0
SIG_WIDTH = 160  # Wider than old 96, narrower than full resolution
MIN_OVERLAP = 40

def grim(region: str, path: str) -> Image.Image | None:
    r = subprocess.run(["grim", "-g", region, path], capture_output=True)
    if r.returncode != 0: return None
    return Image.open(path).convert("RGB")

def signature(img: Image.Image) -> np.ndarray:
    """Grayscale, horizontally downsampled for speed."""
    h = img.height
    small = img.convert("L").resize((SIG_WIDTH, h), Image.BILINEAR)
    return np.asarray(small, dtype=np.float32)

def frame_diff(sa: np.ndarray, sb: np.ndarray) -> float:
    if sa.shape != sb.shape: return 255.0
    return float(np.abs(sa - sb).mean())

def scroll(clicks: int) -> None:
    for _ in range(clicks):
        subprocess.run(["ydotool", "mousemove", "--wheel", "--", "0", "-1"], capture_output=True)

def move_pointer(x: int, y: int) -> None:
    subprocess.run(
        ["hyprctl", "repl", f"hl.dispatch(hl.dsp.cursor.move({{x={x}, y={y}}}))"],
        capture_output=True
    )

def wait_stable(region: str, workdir: str, timeout: float = 3.0) -> tuple[Image.Image, np.ndarray] | None:
    probe = os.path.join(workdir, ".probe.png")
    prev_img = grim(region, probe)
    if not prev_img: return None
    prev_sig = signature(prev_img)
    
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(0.12)
        cur_img = grim(region, probe)
        if not cur_img: return None
        cur_sig = signature(cur_img)
        if frame_diff(prev_sig, cur_sig) < STILL_THRESHOLD * 0.4:
            return cur_img, cur_sig
        prev_sig, prev_img = cur_sig, cur_img
    return prev_img, prev_sig

def find_overlap(sa: np.ndarray, sb: np.ndarray) -> int:
    """Rows shared by bottom of sa and top of sb."""
    limit = min(sa.shape[0], sb.shape[0]) - 1
    best, best_score = 0, float("inf")
    
    # Sweep from large overlap down to minimum
    for d in range(limit, MIN_OVERLAP - 1, -1):
        tail = sa[-d:]
        head = sb[:d]
        score = float(np.abs(tail - head).mean())
        if score < best_score:
            best_score, best = score, d
        if score < 0.5:  # Perfect match
            break
    
    # Accept only if score is reasonable
    if best_score > OVERLAP_THRESHOLD:
        return 0
    return best

def static_band(sigs: list[np.ndarray]) -> int:
    """Height of sticky header: rows identical across all frames."""
    if len(sigs) < 3: return 0
    limit = int(sigs[0].shape[0] * 0.35)
    band = 0
    for row in range(limit):
        first = sigs[0][row]
        if all(float(np.abs(s[row] - first).mean()) < 1.5 for s in sigs[1:]):
            band = row + 1
        else:
            break
    return band

def stitch(frames: list[Image.Image], sigs: list[np.ndarray], band: int) -> Image.Image:
    if not frames: return None
    if len(frames) == 1: return frames[0]
    
    # First frame keeps its sticky band; rest have it cropped
    curr_img = frames[0]
    curr_sig = sigs[0]
    
    for i in range(1, len(frames)):
        nxt_frame = frames[i]
        nxt_sig_full = sigs[i]
        
        # Crop sticky band from this frame
        if band > 0:
            nxt_img = nxt_frame.crop((0, band, nxt_frame.width, nxt_frame.height))
            nxt_sig = nxt_sig_full[band:]
        else:
            nxt_img = nxt_frame
            nxt_sig = nxt_sig_full
        
        ov = find_overlap(curr_sig, nxt_sig)
        
        # Stitch
        new_h = curr_img.height + nxt_img.height - ov
        res = Image.new("RGB", (curr_img.width, new_h))
        res.paste(curr_img, (0, 0))
        
        if ov > 0:
            # Overlap: paste from ov onward
            paste_y = curr_img.height
            crop_top = ov
            res.paste(nxt_img.crop((0, crop_top, nxt_img.width, nxt_img.height)), (0, paste_y))
        else:
            # No overlap: append full next frame (might duplicate content, but safer than skipping)
            res.paste(nxt_img, (0, curr_img.height))
        
        curr_img = res
        curr_sig = signature(curr_img)  # Re-signature the stitched result for next overlap
    
    return curr_img

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", required=True, help="X,Y,W,H")
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", type=int, default=50)
    ap.add_argument("--scroll", type=int, default=5, help="wheel clicks per step")
    ap.add_argument("--manual", action="store_true", help="you scroll, script watches")
    args = ap.parse_args()

    x, y, w, h = (int(v) for v in args.region.split(","))
    reg = f"{x},{y} {w}x{h}"
    
    workdir = tempfile.mkdtemp(prefix="caelestia-scroll-")
    frames, sigs = [], []
    origin = None
    
    def finish(signum, frame_arg):
        try:
            if origin:
                move_pointer(*origin)
        except: pass
        
        if frames:
            band = static_band(sigs)
            res = stitch(frames, sigs, band)
            if res:
                res.save(args.out)
                print(f"{args.out} {res.width}x{res.height} frames={len(frames)} band={band}", file=sys.stderr, flush=True)
        
        shutil.rmtree(workdir, ignore_errors=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, finish)
    signal.signal(signal.SIGINT, finish)

    try:
        # Save cursor position and center over region
        try:
            out = subprocess.check_output(["hyprctl", "cursorpos"], text=True)
            ox, oy = out.strip().split(",")
            origin = (int(ox), int(oy))
        except: pass
        
        move_pointer(x + w // 2, y + h // 2)
        time.sleep(0.15)
        
        # Capture first frame
        res = wait_stable(reg, workdir)
        if not res:
            print("Failed to capture first frame", file=sys.stderr)
            return 1
        frames.append(res[0])
        sigs.append(res[1])
        print(f"Frame 1/{args.frames}", file=sys.stderr, flush=True)

        for i in range(args.frames - 1):
            if not args.manual:
                # Auto: scroll fixed amount
                scroll(args.scroll)
                time.sleep(0.4)
            else:
                # Manual: wait for user to scroll (motion detected)
                print(f"Scroll now... ({i+2}/{args.frames})", file=sys.stderr, flush=True)
                probe_path = os.path.join(workdir, ".motion.png")
                while True:
                    time.sleep(0.2)
                    probe_img = grim(reg, probe_path)
                    if not probe_img: continue
                    probe_sig = signature(probe_img)
                    if frame_diff(sigs[-1], probe_sig) > STILL_THRESHOLD * 1.2:
                        break  # Motion detected
            
            # Wait for content to settle
            res = wait_stable(reg, workdir, timeout=3.5)
            if not res:
                print("Capture failed, stopping", file=sys.stderr)
                break
            
            # Check if we reached the bottom (no change)
            if frame_diff(sigs[-1], res[1]) < STILL_THRESHOLD:
                if not args.manual:
                    print("Bottom reached", file=sys.stderr, flush=True)
                    break
                continue  # In manual mode, keep waiting
            
            frames.append(res[0])
            sigs.append(res[1])
            print(f"Frame {len(frames)}/{args.frames}", file=sys.stderr, flush=True)

        finish(None, None)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        finish(None, None)

if __name__ == "__main__":
    main()
