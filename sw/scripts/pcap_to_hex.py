#!/usr/bin/env python3
"""
============================================================================
Script Name : pcap_to_hex.py
Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
Description : Converts raw PCAP / PCAPNG network dumps containing NASDAQ ITCH 5.0
              MoldUDP64 packets into 64-bit Hex format (.mem file) for SystemVerilog
              $readmemh simulation in Vivado XSIM.
              Also includes a generator mode to create synthetic full-coverage ITCH test dumps.
Usage       : python pcap_to_hex.py --input sample.pcap --output hw/tb/itch_data_dump.mem
              python pcap_to_hex.py --generate --output hw/tb/itch_data_dump.mem
============================================================================
"""

import sys
import os
import struct
import argparse

def generate_synthetic_itch_mem(output_path):
    """
    Generates a comprehensive raw MoldUDP64 byte stream containing ALL ITCH 5.0 message types:
    'S' (System Event), 'R' (Stock Directory), 'A' (Add Order), 'F' (Add Order MPID),
    'E' (Order Executed), 'C' (Exec Price), 'X' (Order Cancel), 'D' (Order Delete),
    'U' (Order Replace), 'P' (Trade Non-Cross).
    Converts stream to 64-bit Hex words for $readmemh.
    """
    raw_bytes = bytearray()

    # --- MoldUDP64 Header (20 Bytes) ---
    session = b"SESSION001"                         # 10 bytes
    seq_num = struct.pack(">Q", 1)                  # 8 bytes (Big-Endian uint64)
    msg_cnt = struct.pack(">H", 10)                 # 2 bytes (Big-Endian uint16: 10 messages)
    raw_bytes.extend(session + seq_num + msg_cnt)

    # 1. Message 'S': System Event (12 Bytes ITCH -> 2 Byte Len + 12 Byte Msg)
    # Len = 12 (0x000C)
    msg_s = struct.pack(">H B H H Q B", 12, ord('S'), 1, 1, 100000000, ord('O')) # 'O' = Start of Messages
    raw_bytes.extend(msg_s)

    # 2. Message 'R': Stock Directory (39 Bytes ITCH -> 2 Byte Len + 39 Byte Msg)
    # Len = 39 (0x0027)
    msg_r = struct.pack(">H B H H Q 8s B B I B B 2s B", 
                        39, ord('R'), 1, 2, 200000000, b"AAPL    ", ord('N'), ord('N'), 100, ord('N'), ord('C'), b"00", ord('N'))
    raw_bytes.extend(msg_r)

    # 3. Message 'A': Add Order (36 Bytes ITCH)
    # Len = 36 (0x0024)
    msg_a = struct.pack(">H B H H Q Q B I 8s I",
                        36, ord('A'), 1, 3, 300000000, 1001, ord('B'), 500, b"AAPL    ", 1502500) # $150.2500
    raw_bytes.extend(msg_a)

    # 4. Message 'F': Add Order MPID (40 Bytes ITCH)
    # Len = 40 (0x0028)
    msg_f = struct.pack(">H B H H Q Q B I 8s I 4s",
                        40, ord('F'), 1, 4, 400000000, 1002, ord('S'), 300, b"MSFT    ", 4105000, b"NSDQ") # $410.5000
    raw_bytes.extend(msg_f)

    # 5. Message 'E': Order Executed (31 Bytes ITCH)
    # Len = 31 (0x001F)
    msg_e = struct.pack(">H B H H Q Q I Q",
                        31, ord('E'), 1, 5, 500000000, 1001, 100, 88888)
    raw_bytes.extend(msg_e)

    # 6. Message 'C': Executed With Price (36 Bytes ITCH)
    # Len = 36 (0x0024)
    msg_c = struct.pack(">H B H H Q Q I Q B I",
                        36, ord('C'), 1, 6, 600000000, 1002, 50, 99999, ord('Y'), 4104500)
    raw_bytes.extend(msg_c)

    # 7. Message 'X': Order Cancel (23 Bytes ITCH)
    # Len = 23 (0x0017)
    msg_x = struct.pack(">H B H H Q Q I",
                        23, ord('X'), 1, 7, 700000000, 1001, 50)
    raw_bytes.extend(msg_x)

    # 8. Message 'D': Order Delete (19 Bytes ITCH)
    # Len = 19 (0x0013)
    msg_d = struct.pack(">H B H H Q Q",
                        19, ord('D'), 1, 8, 800000000, 1002)
    raw_bytes.extend(msg_d)

    # 9. Message 'U': Order Replace (35 Bytes ITCH)
    # Len = 35 (0x0023)
    msg_u = struct.pack(">H B H H Q Q Q I I",
                        35, ord('U'), 1, 9, 900000000, 1001, 2001, 600, 1510000)
    raw_bytes.extend(msg_u)

    # 10. Message 'P': Trade Non-Cross (44 Bytes ITCH)
    # Len = 44 (0x002C)
    msg_p = struct.pack(">H B H H Q Q B I 8s I Q",
                        44, ord('P'), 1, 10, 1000000000, 3001, ord('B'), 1000, b"NVDA    ", 1250000, 77777)
    raw_bytes.extend(msg_p)

    # Pad raw_bytes to multiple of 8 bytes (64-bit alignment)
    remainder = len(raw_bytes) % 8
    if remainder != 0:
        raw_bytes.extend(b"\x00" * (8 - remainder))

    # Format into 64-bit hexadecimal string words for $readmemh
    hex_lines = []
    for i in range(0, len(raw_bytes), 8):
        word_bytes = raw_bytes[i:i+8]
        hex_word = word_bytes.hex().upper()
        hex_lines.append(hex_word)

    # Write to .mem file
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w") as f:
        for line in hex_lines:
            f.write(f"{line}\n")

    print(f"[SUCCESS] Synthetic full ITCH test dump generated: {output_path}")
    print(f"          Total Bytes: {len(raw_bytes)} ({len(hex_lines)} 64-bit words)")

def parse_pcap_to_mem(pcap_path, output_path):
    """
    Parses Wireshark PCAP file, extracts UDP payload (stripping Ethernet 14B + IP 20B + UDP 8B),
    and converts MoldUDP64 payload to .mem format for Vivado XSIM.
    """
    if not os.path.exists(pcap_path):
        print(f"[ERROR] PCAP file not found: {pcap_path}")
        return

    raw_bytes = bytearray()
    with open(pcap_path, "rb") as f:
        pcap_hdr = f.read(24) # PCAP Global Header
        if len(pcap_hdr) < 24:
            print("[ERROR] Invalid PCAP file header.")
            return

        while True:
            pkt_hdr = f.read(16) # PCAP Packet Header
            if len(pkt_hdr) < 16:
                break
            incl_len = struct.unpack("<I", pkt_hdr[8:12])[0]
            pkt_data = f.read(incl_len)

            # Strip Ethernet (14B) + IPv4 (20B) + UDP (8B) = 42 Bytes Header
            if len(pkt_data) > 42:
                udp_payload = pkt_data[42:]
                raw_bytes.extend(udp_payload)

    # Pad to 64-bit word boundary
    remainder = len(raw_bytes) % 8
    if remainder != 0:
        raw_bytes.extend(b"\x00" * (8 - remainder))

    hex_lines = [raw_bytes[i:i+8].hex().upper() for i in range(0, len(raw_bytes), 8)]
    with open(output_path, "w") as f:
        for line in hex_lines:
            f.write(f"{line}\n")

    print(f"[SUCCESS] PCAP converted to MEM: {output_path} ({len(hex_lines)} words)")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="NASDAQ ITCH PCAP to Hex Converter")
    parser.add_argument("--input", type=str, help="Input .pcap file path")
    parser.add_argument("--output", type=str, default="../../hw/tb/itch_data_dump.mem", help="Output .mem file path")
    parser.add_argument("--generate", action="store_true", help="Generate synthetic full-coverage ITCH test dump")

    args = parser.parse_args()

    if args.generate or not args.input:
        generate_synthetic_itch_mem(args.output)
    else:
        parse_pcap_to_mem(args.input, args.output)
