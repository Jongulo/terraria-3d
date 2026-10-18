#!/usr/bin/env python3
"""Builds a labeled contact sheet of sprite crops with ImageMagick (for checking frame coordinates).

usage: python3 -I contact_sheet.py <images dir> <out.png> SHEET:X,Y[,W,H] ...
"""
import os
import subprocess
import sys
import tempfile


def main():
    images, out, specs = sys.argv[1], sys.argv[2], sys.argv[3:]
    with tempfile.TemporaryDirectory() as tmp:
        args = []
        for i, spec in enumerate(specs):
            sheet, coords = spec.split(":")
            nums = [int(v) for v in coords.split(",")]
            x, y = nums[0], nums[1]
            w, h = (nums[2], nums[3]) if len(nums) == 4 else (16, 16)
            crop = os.path.join(tmp, f"{i}.png")
            subprocess.run(["magick", os.path.join(images, sheet + ".png"), "-crop", f"{w}x{h}+{x}+{y}", "+repage", "-scale", "500%", crop], check=True)
            args += ["-label", spec, crop]
        subprocess.run(["montage", *args, "-tile", "8x", "-geometry", "+4+4", "-background", "gray60", out], check=True)


if __name__ == "__main__":
    main()
