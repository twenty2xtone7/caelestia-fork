#!/usr/bin/env python3
"""Stitch vertically scrolled screenshots into one tall image.

Finds overlap between consecutive frames by searching for the best
matching region, then crops & concatenates. Handles cases where content
scrolls past, reappears, or repeats.
"""
import sys
import glob
from PIL import Image
import numpy as np

def load_images(pattern):
    """Load images matching glob pattern, sorted by name."""
    files = sorted(glob.glob(pattern))
    if not files:
        print(f"No images found matching {pattern}", file=sys.stderr)
        sys.exit(1)
    return [Image.open(f).convert('RGB') for f in files]

def find_overlap(prev_img, curr_img, max_search=300):
    """Find vertical overlap between bottom of prev and top of curr.
    
    Returns the number of pixels of overlap (0 if none found).
    """
    search_range = min(prev_img.height, curr_img.height, max_search)
    
    # Convert to numpy for vectorized operations
    prev_arr = np.array(prev_img.crop((0, prev_img.height - search_range, 
                                       prev_img.width, prev_img.height)), dtype=np.float32)
    curr_arr = np.array(curr_img.crop((0, 0, curr_img.width, search_range)), 
                       dtype=np.float32)
    
    best_overlap = 0
    best_score = float('inf')
    
    # Search for best match by trying different overlap amounts
    for overlap_px in range(search_range, max(0, search_range - 100), -1):
        # Take bottom 'overlap_px' of prev, top 'overlap_px' of curr
        p_slice = prev_arr[-overlap_px:, :, :]
        c_slice = curr_arr[:overlap_px, :, :]
        
        # Sum of squared differences (SSD)
        diff = np.sum((p_slice - c_slice) ** 2)
        
        if diff < best_score:
            best_score = diff
            best_overlap = overlap_px
            
            # Early exit if near-perfect match
            if diff < 100 * overlap_px * prev_img.width:
                break
    
    return best_overlap

def stitch(images, output_path):
    """Stitch images together by finding overlaps."""
    if not images:
        print("No images to stitch", file=sys.stderr)
        return False
    
    if len(images) == 1:
        images[0].save(output_path)
        return True
    
    result = images[0]
    
    for i in range(1, len(images)):
        prev = result
        curr = images[i]
        
        overlap = find_overlap(prev, curr)
        
        # Stitch: place current below prev, offset by overlap
        new_height = prev.height + curr.height - overlap
        combined = Image.new('RGB', (prev.width, new_height))
        combined.paste(prev, (0, 0))
        combined.paste(curr, (0, prev.height - overlap))
        result = combined
    
    result.save(output_path)
    print(f"Stitched {len(images)} frames → {output_path} ({result.width}x{result.height})")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: stitch_scroll.py <glob_pattern> <output_path>", file=sys.stderr)
        print("Example: stitch_scroll.py '/tmp/scroll-*.png' /tmp/stitched.png", file=sys.stderr)
        sys.exit(1)
    
    pattern = sys.argv[1]
    output = sys.argv[2]
    
    images = load_images(pattern)
    if not stitch(images, output):
        sys.exit(1)
