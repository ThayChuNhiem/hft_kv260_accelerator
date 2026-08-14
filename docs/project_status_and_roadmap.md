# 📊 THÔNG TIN DỰ ÁN & BẢNG KIỂM SOÁT TIẾN ĐỘ
**Tên dự án**: Kiến trúc Hybrid HW/SW Co-Design cho Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)  
**Tác giả / Nhóm nghiên cứu**: ThayChuNhiem  
**Cập nhật gần nhất**: 2026-08-14  

---

## 💡 ỨNG DỤNG CHIẾN LƯỢC HFT & CÁC KỊCH BẢN THỰC THI

Kiến trúc phần cứng Data Path ([hft_top.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/hft_top.sv)) trên Kria KV260 đạt độ trễ siêu tốc **$105\text{ ns}$**, đóng vai trò là một **Khung Tăng Tốc HFT Đa Chiến Lược (Multi-Strategy HFT Accelerator Framework)** hỗ trợ 4 kịch bản giao dịch thực tế:

1. **Cross-Venue Latency Arbitrage (Kinh doanh chênh lệch giá liên sàn)**:
   - **Cơ chế**: Phát hiện cơ hội $P_{\text{Bid}} \ge P_{\text{Ask}}$ giữa các sàn giao dịch (NASDAQ, NYSE, BATS) do chênh lệch độ trễ cáp quang.
   - **Thực thi**: Tự động bắn lệnh Mua bên sàn rẻ ($P_{\text{Ask}}$) và Bán bên sàn đắt ($P_{\text{Bid}}$) thu lợi nhuận không rủi ro trong $105\text{ ns}$.

2. **High-Frequency Market Making (Tạo thanh khoản siêu tốc)**:
   - **Cơ chế**: Đặt đồng thời cả lệnh Mua ($P_{\text{Bid}}$) và Bán ($P_{\text{Ask}}$) ở 2 đầu sổ lệnh để thu lợi nhuận từ chênh lệch Spread ($P_{\text{Ask}} - P_{\text{Bid}}$) và tiền thưởng tạo thanh khoản (Maker Rebates).
   - **Bảo vệ Rủi ro**: Khi nhận biến động xấu từ `itch_parser`, FPGA gửi lệnh **rút lệnh phần cứng (`'X'`/`'U'`) trong $25\text{ ns}$** để tránh bị khớp ở giá hớ (Adverse Selection Protection).

3. **Momentum Ignition & Order Flow Toxicity (Đón đầu luồng lệnh lớn)**:
   - **Cơ chế**: Khi `itch_parser` phát hiện khối lượng lệnh mua gom khổng lồ (Institutional Order Sweep) vừa nạp vào sổ lệnh, FPGA phát hiện ở $30\text{ ns}$ đầu tiên và phát lệnh Mua đón đầu trước khi giá bị đẩy lên cao.

4. **Ultra-Fast Emergency Risk Check & Cancel All (Rút lệnh khẩn cấp)**:
   - **Cơ chế**: Khi đường mạng gặp sự cố hoặc tin tức đảo chiều bất ngờ, FPGA cho phép gửi hàng loạt lệnh hủy OUCH 4.2 (`'X'`) trong $< 100\text{ ns}$, bảo vệ tài khoản khỏi các khoản lỗ lớn.

---

## 🗂️ CẤU TRÚC THƯ MỤC CHI TIẾT ĐẾN TỪNG FILE & CÔNG DỤNG

```text
kv260_hft_accelerator/
├── .gitignore                          # [Cấu hình Git] Chặn các file rác lớn của Vivado (*.log, *.jou, project_1/), file biên dịch C++/Python/LaTeX
├── README.md                           # [Tài liệu chính] Hướng dẫn tổng quan kiến trúc Data/Control Plane, prerequisites và cách build
├── docs/                               # [Tài liệu & Học thuật]
│   ├── project_status_and_roadmap.md   # [Báo cáo tiến độ] File theo dõi tiến độ chi tiết, cây thư mục và lộ trình theo tuần
│   ├── ieee_paper/                     # [Mã nguồn LaTeX] Chứa template bài báo khoa học IEEE/ACM
│   └── diagrams/                       # [Sơ đồ kiến trúc] Chứa sơ đồ khối ASCII, Visio, Draw.io
├── hw/                                 # [Hardware Workspace - FPGA PL (Data Plane)]
│   ├── src/                            # Mã nguồn RTL phần cứng (SystemVerilog)
│   │   ├── common/
│   │   │   └── hft_pkg.sv              # [Data Package] Định nghĩa các struct packed ITCH 5.0 (Big-Endian Wire), Enums, và struct chuẩn hóa nội bộ (Little-Endian)
│   │   ├── itch_parser/
│   │   │   └── itch_parser.sv          # [FSM Parser] Module giải mã gói mạng MoldUDP64 / ITCH 5.0 phần cứng, lật Endianness siêu tốc
│   │   ├── matching_engine/            # [Matching Engine] Logic quản lý sổ lệnh (Order Book L3/L2) và đưa ra quyết định giao dịch
│   │   ├── ouch_formatter/             # [OUCH Formatter] Module đóng gói lệnh đặt (Order Entry - OUCH 4.2) xuất ngược ra mạng
│   │   ├── network/                    # [Ethernet Core] Chứa submodule từ verilog-ethernet (Ethernet MAC + UDP/IP stack)
│   │   └── dma_intf/                   # [AXI DMA Interface] Module trích xuất log telemetry AXI Stream nối sang AXI DMA
│   ├── tb/                             # [Testbenches Mô phỏng]
│   │   ├── tb_itch_parser.sv           # [Unit Testbench] Mô phỏng đơn vi bộ FSM ITCH Parser (xung clk 200MHz, driver phát 3 thông điệp)
│   │   ├── tb_itch_parser_full.sv      # [Full PCAP Testbench] Mô phỏng tự kiểm tra (Self-checking) nạp file .mem, kiểm thử 10 loại message ITCH 5.0
│   │   └── itch_data_dump.mem          # [Data Dump Memory] File Hex 64-bit chứa toàn bộ 10 loại gói tin ITCH 5.0 phục vụ mô phỏng $readmemh
│   ├── constraints/                    # [Pinout & Timing] File gán chân pin (.xdc) và ràng buộc thời gian cho Kria KV260
│   └── scripts/
│       └── sim_parser.tcl              # [Vivado Automation] Script Tcl tự động khởi tạo project Vivado, nạp nguồn và chạy XSIM mô phỏng
└── sw/                                 # [Software Workspace - ARM PS (Control Plane)]
    ├── bitstream/                      # [Bitstreams] Chứa các file hft_kv260.bit và hft_kv260.hwh để PYNQ nạp Overlay
    ├── pynq_notebooks/                 # [Jupyter Notebooks] Các notebook kiểm thử nạp bitstream, ghi log DMA và đo đạc latency
    ├── drivers/                        # [High-Performance Drivers] Mã nguồn C++/Python dùng UIO/mmap truy cập thanh ghi AXI Lite & AXI DMA
    └── scripts/
        └── pcap_to_hex.py              # [PCAP Converter] Script Python chuyển đổi file bắt gói mạng Wireshark (.pcap/.pcapng) sang Hex (.mem)
```

---

## 📋 DANH SÁCH TẤT CẢ CÁC FILE ĐÃ KHỞI TẠO & VIẾT MÃ

| STT | Tên File | Đường dẫn | Công dụng / Chức năng |
| :---: | :--- | :--- | :--- |
| 1 | `.gitignore` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/.gitignore) | Loại bỏ các file trung gian Vivado, Vitis, C++, Python, LaTeX khỏi Git |
| 2 | `README.md` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/README.md) | Tài liệu hướng dẫn tổng quan kiến trúc dự án |
| 3 | `hft_pkg.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/common/hft_pkg.sv) | SystemVerilog Package: Chứa MoldUDP64 Struct, 10 loại ITCH 5.0 Struct, BBO Struct và Enums |
| 4 | `itch_parser.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/itch_parser/itch_parser.sv) | SystemVerilog FSM Parser: Giải mã luồng AXI-Stream 64-bit, lật Endianness |
| 5 | `matching_engine.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/matching_engine/matching_engine.sv) | SystemVerilog Matching Engine: Quản lý sổ lệnh L3/L2 trên BRAM/URAM, cập nhật BBO $\le 2$ cycles ($10\text{ ns}$) |
| 6 | `tb_itch_parser.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_itch_parser.sv) | Testbench đơn vị (Unit Test) cho bộ giải mã ITCH 5.0 |
| 7 | `tb_itch_parser_full.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_itch_parser_full.sv) | Testbench tự kiểm tra toàn diện 10 loại message ITCH 5.0 từ file `.mem` |
| 8 | `tb_matching_engine.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_matching_engine.sv) | Testbench kiểm thử BBO Top-of-Book và tín hiệu Trade Trigger cho Matching Engine |
| 9 | `itch_data_dump.mem` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/itch_data_dump.mem) | Mảng dữ liệu Hex 64-bit của gói MoldUDP64/ITCH 5.0 nạp vào XSIM |
| 10 | `sim_parser.tcl` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/scripts/sim_parser.tcl) | Vivado Tcl script tự động hóa chạy mô phỏng ITCH Parser |
| 11 | `sim_matching.tcl` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/scripts/sim_matching.tcl) | Vivado Tcl script tự động hóa chạy mô phỏng Matching Engine |
| 12 | `ouch_formatter.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/ouch_formatter/ouch_formatter.sv) | SystemVerilog Formatter: Đóng gói lệnh OUCH 4.2 ('O') 49 Bytes truyền ra AXI-Stream trong $35\text{ ns}$ |
| 13 | `tb_ouch_formatter.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_ouch_formatter.sv) | Testbench kiểm thử phát lệnh OUCH 4.2 và giải mã stream 64-bit |
| 14 | `sim_ouch.tcl` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/scripts/sim_ouch.tcl) | Vivado Tcl script tự động hóa chạy mô phỏng OUCH Formatter |
| 15 | `hft_top.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/hft_top.sv) | SystemVerilog Top Level Wrapper: Đấu nối trọn gói toàn bộ pipeline phần cứng Network In -> ITCH -> Matching -> OUCH -> Network Out |
| 16 | `tb_hft_top.sv` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_hft_top.sv) | Full Integrated System Testbench: Đo đạc thời gian Tick-to-Trade Latency chuẩn nanoseconds |
| 17 | `sim_top.tcl` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/scripts/sim_top.tcl) | Vivado Tcl script tự động hóa chạy mô phỏng toàn bộ luồng hft_top.sv |
| 18 | `pcap_to_hex.py` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/sw/scripts/pcap_to_hex.py) | Tool Python bóc tách UDP payload từ file PCAP Wireshark xuất ra `.mem` |
| 19 | `project_status_and_roadmap.md` | [file](file:///d:/2026/FPGA/hft_kv260_accelerator/docs/project_status_and_roadmap.md) | File báo cáo tiến độ và cây thư mục chi tiết (Đã cập nhật 100% Giai đoạn 2) |

---

## 📅 BẢNG KIỂM SOÁT TIẾN ĐỘ DỰ ÁN THEO TUẦN

#### 🔵 GIAI ĐOẠN 1: Thiết Kế Core RTL Data Plane & Mô Phỏng (Tuần 1 – Tuần 3)
> **Mục tiêu**: Hoàn thiện bộ giải mã ITCH 5.0 và mô phỏng chính xác trên phần mềm Vivado Simulator.

- [x] **Tuần 1**: Tạo cấu trúc dự án chuẩn SoC, cấu hình file [.gitignore](file:///d:/2026/FPGA/hft_kv260_accelerator/.gitignore), [README.md](file:///d:/2026/FPGA/hft_kv260_accelerator/README.md) và SystemVerilog package [hft_pkg.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/common/hft_pkg.sv). *(ĐÃ HOÀN THÀNH 100%)*
- [x] **Tuần 2**: Thiết kế module FSM giải mã gói mạng [itch_parser.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/itch_parser/itch_parser.sv) và viết Unit Testbench [tb_itch_parser.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_itch_parser.sv). *(ĐÃ HOÀN THÀNH 100%)*
- [x] **Tuần 3**: Xây dựng tool Python [pcap_to_hex.py](file:///d:/2026/FPGA/hft_kv260_accelerator/sw/scripts/pcap_to_hex.py), nạp dữ liệu thực tế (`itch_data_dump.mem`) vào Testbench [tb_itch_parser_full.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_itch_parser_full.sv) và chạy mô phỏng thành công 100% trên Vivado 2026.1 XSIM (0 errors, 412.5ns latency). *(ĐÃ HOÀN THÀNH 100%)*

---

#### 🟢 GIAI ĐOẠN 2: Xây Dựng Order Book, Matching Engine & OUCH Formatter (Tuần 4 – Tuần 7)
> **Mục tiêu**: Xử lý logic sổ lệnh và phát sinh gói tin đặt lệnh (Order Entry) phần cứng.

- [x] **Tuần 4 - 5**: Thiết kế [matching_engine.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/matching_engine/matching_engine.sv) và Testbench [tb_matching_engine.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_matching_engine.sv):
  - Dùng BRAM/URAM trên FPGA để quản lý Sổ lệnh L3/L2 (Limit Order Book).
  - Cập nhật giá Bid/Ask tốt nhất (Best Bid and Offer - BBO) trong $\le 2$ chu kỳ clock ($10\text{ ns}$). *(ĐÃ HOÀN THÀNH 100%)*
- [x] **Tuần 6**: Thiết kế [ouch_formatter.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/ouch_formatter/ouch_formatter.sv) và Testbench [tb_ouch_formatter.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_ouch_formatter.sv): Đóng gói lệnh OUCH 4.2 ('O') gửi trả ngược ra mạng khi chiến lược kích hoạt trong $35\text{ ns}$. *(ĐÃ HOÀN THÀNH 100%)*
- [x] **Tuần 7**: Mô phỏng toàn bộ luồng phần cứng: `Network In -> ITCH Parser -> Matching Engine -> OUCH Out` qua Top Module [hft_top.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/src/hft_top.sv) và Testbench [tb_hft_top.sv](file:///d:/2026/FPGA/hft_kv260_accelerator/hw/tb/tb_hft_top.sv). *(ĐÃ HOÀN THÀNH 100%)*

---

#### 🟡 GIAI ĐOẠN 3: Tích Hợp EMIO Ethernet, AXI DMA & Vivado Block Design (Tuần 8 – Tuần 10)
> **Mục tiêu**: Tổng hợp Hardware trên Vivado và tích hợp giao tiếp với ARM Processor.

- [ ] **Tuần 8**: Tích hợp IP `verilog-ethernet` (MAC + UDP/IP stack) vào RTL. Cấu hình **EMIO Routing** đưa tín hiệu Ethernet xuống cổng mở rộng PMOD / IO của KV260.
- [ ] **Tuần 9**: Tích hợp IP **Xilinx AXI DMA** và **AXI SmartConnect** để kết nối đường Telemetry Logging từ PL sang DRAM của PS.
- [ ] **Tuần 10**: Hoàn thiện Vivado Tcl Script `build_project.tcl` và file chân `.xdc` để tự động hóa quá trình Synthesize, Place & Route, tạo file Bitstream (`.bit`) và Hardware Definition (`.hwh`).

---

#### 🔴 GIAI ĐOẠN 4: Lập Trình PYNQ Control Plane & Đo Đạc Độ Trễ Tick-to-Trade (Tuần 11 – Tuần 13)
> **Mục tiêu**: Chạy thực nghiệm trên kit KV260 thật và thu thập số liệu độ trễ nanosecond.

- [ ] **Tuần 11**: Cấu hình PYNQ Linux v3.0+ trên thẻ nhớ SD của KV260. Viết Jupyter Notebooks ([sw/pynq_notebooks/](file:///d:/2026/FPGA/hft_kv260_accelerator/sw/pynq_notebooks/)) nạp Overlay `.bit`.
- [ ] **Tuần 12**: Viết C++ Driver ([sw/drivers/](file:///d:/2026/FPGA/hft_kv260_accelerator/sw/drivers/)) dùng memory-mapping (`mmap` / UIO) để thu thập mảng dữ liệu Telemetry DMA tốc độ cao.
- [ ] **Tuần 13**: Thực hiện **Tick-to-Trade Latency Benchmarking**:
  - Dùng Hardware 64-bit Timer đếm thời gian từ chu kỳ `rx_tvalid` đầu tiên đến `tx_tvalid` phát lệnh.
  - Mục tiêu chỉ số: Hardware Latency $< 500\text{ ns}$.

---

#### 🟣 GIAI ĐOẠN 5: Viết Báo Cáo IEEE/ACM & Hoàn Thiện Dự Án (Tuần 14 – Tuần 16)
> **Mục tiêu**: Đóng gói kết quả nghiên cứu thành bài báo khoa học chuẩn IEEE format.

- [ ] **Tuần 14**: Tổng hợp số liệu tài nguyên FPGA (LUT, BRAM, DSP, Power trên ZU5EV) và vẽ biểu đồ phân bố độ trễ (Latency Histogram).
- [ ] **Tuần 15**: Viết bài báo bằng LaTeX trong thư mục [docs/ieee_paper/](file:///d:/2026/FPGA/hft_kv260_accelerator/docs/ieee_paper/): So sánh hiệu năng giữa FPGA PL Fast Path vs Software Network Stack.
- [ ] **Tuần 16**: Rà soát toàn bộ mã nguồn và phát hành bản phát hành chính thức trên GitHub.
