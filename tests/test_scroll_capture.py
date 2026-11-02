import unittest
import numpy as np
from PIL import Image
import sys, os, tempfile, shutil

# Load scroll-capture.py directly
import importlib.util
spec = importlib.util.spec_from_file_location(
    "scroll_capture",
    os.path.join(os.path.dirname(__file__), "..", "tools", "scroll-capture.py")
)
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)

def make_page(h: int, w: int, seed: int) -> Image.Image:
    rng = np.random.default_rng(seed)
    arr = np.zeros((h, w, 3), dtype=np.uint8)
    for y in range(h):
        val = (y * 7 + seed * 13) % 256
        arr[y, :, 0] = val
        arr[y, :, 1] = (val + 85) % 256
        arr[y, :, 2] = (val + 170) % 256
    noise = rng.integers(-20, 20, size=(h, w, 3), dtype=np.int16)
    arr = np.clip(arr.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    return Image.fromarray(arr)

class TestWaitStable(unittest.TestCase):
    def test_returns_first_when_still(self):
        img = make_page(200, 120, 1)
        with tempfile.TemporaryDirectory() as tmp:
            region = "0,0 120x200"
            original = sc.grim
            def fake_grim(reg, path): return img.copy()
            sc.grim = fake_grim
            result = sc.wait_stable(region, tmp, timeout=0.3)
            sc.grim = original
        self.assertEqual(result[0], img)

class TestStitchOverlap(unittest.TestCase):
    def test_three_frame_tall(self):
        w, h = 120, 200
        page = make_page(500, w, 7)
        frames, sigs = [], []
        top = 0
        for ov in [60, 45]:
            f = page.crop((0, top, w, top + h))
            frames.append(f)
            sigs.append(sc.signature(f))
            top += h - ov
        f = page.crop((0, top, w, min(top + h, page.height)))
        frames.append(f)
        sigs.append(sc.signature(f))
        
        result = sc.stitch(frames, sigs, 0)
        self.assertEqual(result.width, w)
        self.assertGreaterEqual(result.height, 450)

if __name__ == "__main__":
    unittest.main()
