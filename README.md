# Hybrid HW/SW Co-Design for Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)

Dự án nghiên cứu xây dựng **Kiến trúc Tăng tốc HFT (High-Frequency Trading) Hybrid Hardware/Software Co-Design** đạt độ trễ siêu thấp (Sub-Microsecond Latency) trên bo mạch **AMD Xilinx Kria KV260 Vision AI Starter Kit (Zynq UltraScale+ MPSoC EG)**.

---

## 📌 Tổng Quan Kiến Trúc (Architecture Overview)

Dự án phân chia hệ thống thành 2 phân vùng theo nguyên lý **Data Plane / Control Plane**:

1. **Hardware Data Plane (FPGA Programmable Logic - PL): Fast Path (Zero-Copy)**
   - **Network Stack**: Nhận luồng gói tin Ethernet/UDP qua EMIO / PL Ethernet MAC (`verilog-ethernet`).
   - **NASDAQ ITCH 5.0 Parser**: Bộ giải mã gói tin thị trường bằng FSM (Finite State Machine) phần cứng độ trễ siêu thấp.
   - **Order Book & Matching / Strategy Engine**: Cập nhật sổ lệnh và đưa ra quyết định đặt lệnh (Order Entry - OUCH) hoàn toàn trong phần cứng.
   - **AXI DMA Interface**: Trích xuất dữ liệu telemetry/log đẩy sang bộ nhớ DDR của PS.

2. **Software Control Plane (ARM Processing System - PS): Slow Path / Telemetry**
   - **PYNQ Framework & Linux OS**: Quản lý nạp Bitstream (`Overlay`), cấu hình tham số chiến lược qua AXI Lite.
   - **AXI DMA Driver**: Đọc log/dữ liệu khớp lệnh từ PL qua giao tiếp memory-mapped (Zero-copy DMA).

---

## 📂 Cấu Trúc Thư Mục (Repository Structure)

```text
kv260_hft_accelerator/
├── .gitignore                   # Chặn *.jou, *.log, project_1/, *.bit, *.hdf, etc.
├── README.md                    # Hướng dẫn build dự án & tổng quan
├── docs/                        # Tài liệu học thuật & Kiến trúc hệ thống
│   ├── ieee_paper/              # Mã nguồn LaTeX bài báo IEEE/ACM
│   └── diagrams/                # Sơ đồ kiến trúc (ASCII, Draw.io, Visio)
├── hw/                          # Hardware Workspace (Data Plane - PL)
│   ├── src/                     # Mã nguồn RTL (Verilog/SystemVerilog)
│   │   ├── common/              # SystemVerilog packages, Structs & Headers
│   │   ├── network/             # Ethernet MAC / UDP Parser (verilog-ethernet)
│   │   ├── itch_parser/         # FSM giải mã NASDAQ ITCH 5.0
│   │   ├── matching_engine/     # Logic khớp lệnh / Chiến lược HFT
│   │   ├── ouch_formatter/      # Formatter tạo gói tin Order Entry (OUCH 4.2)
│   │   └── dma_intf/            # Giao tiếp AXI Stream với AXI DMA IP
│   ├── tb/                      # Testbench mô phỏng SystemVerilog (Unit & Top TB)
│   ├── constraints/             # KV260 Pinout & Timing (.xdc)
│   └── scripts/                 # Tcl scripts tự động hóa Vivado Block Design
└── sw/                          # Software Workspace (Control Plane - PS)
    ├── bitstream/               # Chứa file .bit và .hwh đã biên dịch cho PYNQ
    ├── pynq_notebooks/          # Jupyter Notebooks kiểm thử & thu thập Log
    ├── drivers/                 # C++/Python AXI DMA & AXI-Lite MMIO Drivers
    └── scripts/                 # Scripts cấu hình môi trường Linux trên KV260
```

---

## 🛠️ Yêu Cầu Môi Trường (Prerequisites)

- **Hardware**: AMD Xilinx Kria KV260 Vision AI Starter Kit (Zynq UltraScale+ MPSoC ZCU104/ZCU102 tương đương).
- **Software Toolchain**:
  - AMD Xilinx Vivado ML Edition (>= 2022.1 / 2023.1).
  - PYNQ Image v3.0+ cài đặt trên thẻ nhớ MicroSD cho KV260.
  - Python 3.8+ (với `pynq`, `numpy`, `pandas`, `matplotlib`).
  - GCC / Clang C++17 compiler (cho C++ high-performance driver).

---

## 🚀 Hướng Dẫn Build & Chạy Thử (Quick Start)

### 1. Build Hardware (Vivado PL)
```bash
cd hw/scripts
vivado -mode batch -source build_project.tcl
```
*Kết quả sẽ xuất file `hft_kv260.bit` và `hft_kv260.hwh` vào thư mục `sw/bitstream/`.*

### 2. Chạy Software Control Plane (PYNQ / PS)
1. Khởi động KV260 với PYNQ SD Card và kết nối SSH / Jupyter Notebook (`http://<kv260_ip>:8888`).
2. Copy thư mục `sw/` lên KV260.
3. Mở Jupyter Notebook `sw/pynq_notebooks/01_hft_dma_test.ipynb` để nạp overlay và thử nghiệm nhận/gửi data telemetry qua AXI DMA.

---

## 📜 Giấy Phép & Tác Giả (License & Citation)
- **Dự án**: *Kiến trúc Hybrid HW/SW Co-Design cho Tick-to-Trade HFT Accelerator*.
- **Thiết kế cho**: AMD Xilinx Kria KV260 FPGA.
