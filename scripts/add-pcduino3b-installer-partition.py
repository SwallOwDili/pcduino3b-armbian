#!/usr/bin/env python3
"""Append the fixed FAT32 payload/log partition to an installer-card image."""

from __future__ import annotations

import argparse
import os
import struct
from pathlib import Path


SECTOR_BYTES = 512
ALIGNMENT_SECTORS = 2048
PAYLOAD_BYTES = 768 * 1024 * 1024
MBR_SIGNATURE = b"\x55\xaa"


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def partition(raw: bytes, index: int) -> tuple[int, int, int]:
    offset = 446 + index * 16
    return raw[offset + 4], *struct.unpack_from("<II", raw, offset + 8)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--payload-bytes", type=int, default=PAYLOAD_BYTES)
    args = parser.parse_args()

    image = args.image.resolve()
    payload_bytes = args.payload_bytes
    if payload_bytes <= 0 or payload_bytes % SECTOR_BYTES:
        raise SystemExit("payload size must be a positive whole number of sectors")

    with image.open("r+b") as handle:
        mbr = bytearray(handle.read(SECTOR_BYTES))
        if len(mbr) != SECTOR_BYTES or mbr[510:512] != MBR_SIGNATURE:
            raise SystemExit("input lacks a valid DOS MBR")

        p1_type, p1_start, p1_sectors = partition(mbr, 0)
        if p1_type != 0x83 or p1_start != 8192 or p1_sectors == 0:
            raise SystemExit(
                "partition 1 is not the expected pcDuino3B Linux root partition"
            )
        for index in range(1, 4):
            if partition(mbr, index) != (0, 0, 0):
                raise SystemExit(f"partition entry {index + 1} is already occupied")

        current_bytes = image.stat().st_size
        if current_bytes % SECTOR_BYTES:
            raise SystemExit("input image length is not sector-aligned")
        p1_end = p1_start + p1_sectors
        p2_start = align_up(max(p1_end, current_bytes // SECTOR_BYTES), ALIGNMENT_SECTORS)
        p2_sectors = payload_bytes // SECTOR_BYTES
        final_sectors = p2_start + p2_sectors
        if final_sectors > 0xFFFFFFFF:
            raise SystemExit("result exceeds the DOS MBR LBA range")

        # Saturated CHS values make the entry unambiguously LBA-addressed.
        entry = struct.pack(
            "<B3sB3sII",
            0,
            b"\xfe\xff\xff",
            0x0C,
            b"\xfe\xff\xff",
            p2_start,
            p2_sectors,
        )
        mbr[462:478] = entry
        handle.seek(0)
        handle.write(mbr)
        handle.truncate(final_sectors * SECTOR_BYTES)
        handle.flush()
        os.fsync(handle.fileno())

    print(f"P1_START_SECTORS={p1_start}")
    print(f"P1_SIZE_SECTORS={p1_sectors}")
    print(f"P2_START_SECTORS={p2_start}")
    print(f"P2_SIZE_SECTORS={p2_sectors}")
    print(f"FINAL_BYTES={final_sectors * SECTOR_BYTES}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
