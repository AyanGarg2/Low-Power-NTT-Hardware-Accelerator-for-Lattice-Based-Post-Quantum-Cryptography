# Low-Power NTT Hardware Accelerator for Lattice-Based Post-Quantum Cryptography

> RTL-to-GDS implementation of an efficient, flexible Number Theoretic Transform (NTT) core for post-quantum cryptographic schemes, based on the IEEE HOST 2019 paper by Fritzmann & Sepulveda.

---

## Overview

This project implements a complete, low-power hardware accelerator for the Number Theoretic Transform (NTT) and its inverse (INTT), targeting post-quantum cryptographic schemes such as **CRYSTALS-Kyber** and **NewHope**. Quantum computers threaten classical public-key systems (RSA, ECC); lattice-based cryptography is a leading post-quantum alternative, and NTT is its most compute-intensive building block.

The design is described in synthesisable **Verilog-2005** and covers the full implementation flow:
- Functional verification via cycle-accurate Python simulation and Vivado behavioural simulation
- FPGA prototyping on the Xilinx **Zynq-7020**
- ASIC synthesis and place-and-route using Cadence **Genus/Innovus** on **UMC 130 nm**

The project was completed as part of **EE593: Low Power VLSI Design** at the Indian Institute of Technology Mandi, under the guidance of **Dr. Srinivasu Bodapati**.

---

## Team

| Name | Roll No. |
|---|---|
| Krishna Gorai | T25111 |
| Achal Shah | T25119 |
| Ayan Garg | B23484 |

---

## Reference Paper

> T. Fritzmann and J. Sepulveda, **"Efficient and Flexible Low-Power NTT for Lattice-Based Cryptography,"** in *Proc. IEEE International Symposium on Hardware Oriented Security and Trust (HOST)*, McLean, VA, USA, 2019, pp. 141–150.

---

## Architecture

The NTT core is a **single-port, memory-based Cooley-Tukey butterfly** controlled by a 12-state FSM. It consists of four main modules:

| Module | Description |
|---|---|
| **RAM** | Single-port RAM storing two 16-bit coefficients per 32-bit memory line (n/2 × 32 bits) |
| **Address Unit** | Controls read/write addresses and write-enable for RAM access |
| **ω/α Update Unit** | Updates twiddle factor ω and inverse-NTT scaling factors α₁–α₄ each cycle |
| **Butterfly Core** | Performs Montgomery multiplication and Barrett reduction; additional multipliers (shown in red in the block diagram) activate only during INTT |

**Registers:** H1 and L1 hold the high and low 16-bit coefficients from RAM. R1–R5 store intermediate results and enable coefficient swapping between rounds.

### Algorithms Implemented

| Algorithm | Description |
|---|---|
| **Alg. 2** – Barrett Reduction | Modular reduction for additions/subtractions; replaces division with multiply + shift |
| **Alg. 3** – Montgomery Reduction | Modular multiplication using multiply, mask, and shift; avoids hardware dividers |
| **Alg. 4** – Optimised NTT (First Rounds) | Cooley-Tukey butterfly with integrated Montgomery and Barrett reduction; negacyclic pre-processing folded into twiddle initialisation |
| **Alg. 5** – Optimised INTT (Last Round) | Post-processing (n⁻¹ scaling and γ⁻ⁱ de-rotation) folded into the last round, saving at least 2n clock cycles |

### Supported Parameter Sets

| Scheme | n | q | ωₙ |
|---|---|---|---|
| CRYSTALS-Kyber | 256 | 7681 | 5685 |
| NewHope-512 | 512 | 12289 | 3400 |
| NewHope-1024 | 1024 | 12289 | 10302 |

All parameters (n, q, q′, LUT contents, scaling factors) are **runtime-configurable** — no re-synthesis is required to switch parameter sets.

---

## Power Optimisation Techniques

Three techniques from the reference paper are implemented at the RTL level:

**1. Operand Isolation — INTT Multipliers**
Inputs to the α-scaling multipliers are forced to zero outside the last round, preventing unnecessary switching and eliminating their dynamic power contribution during the forward NTT.

**2. Operand Isolation — Input Registers**
H1 and L1 are clock-gated during write cycles. A latch after the first multiplier blocks propagation when the result is not needed, reducing switching in the butterfly datapath.

**3. Integrated Clock Gating (ICG)**
Registers sharing a common enable signal are grouped. Cadence Genus infers ICG cells from RTL `if(bf_act)` enables, disabling inactive registers and reducing their dynamic power to zero.

Combined, these techniques achieve **>30% dynamic power reduction** versus an unoptimised baseline, consistent with the reference paper.

---

## Results

### FPGA — Xilinx Zynq-7020 (xc7z020clg484-1)

| Resource | This Work | Paper [1] | Available | Util. |
|---|---|---|---|---|
| LUT (total) | 1,221 | 980 | 53,200 | 2.30% |
| LUT as Logic | 953 | — | 53,200 | 1.79% |
| LUT as Dist. RAM | 268 | — | 17,400 | 1.54% |
| Registers (FF) | 573 | 395 | 106,400 | 0.54% |
| DSP48E1 | 25 | 26 | 220 | 11.36% |

**FPGA Power (20 MHz, SAIF-annotated, Typical):**

| n | Operation | P_static (mW) | P_dyn (mW) | P_total (mW) |
|---|---|---|---|---|
| 256 | NTT | 131 | 10 | 141 |
| 256 | INTT | 131 | 11 | 142 |
| 512 | NTT | 131 | 10 | 141 |
| 512 | INTT | 131 | 11 | 142 |
| 1024 | NTT | 131 | 11 | 141 |
| 1024 | INTT | 131 | 11 | 142 |

Dynamic power is n-independent (single-butterfly architecture). INTT draws ~1 mW more than NTT due to α-scaling activity in the last round.

---

### ASIC — UMC 130 nm (Cadence Genus + Innovus)

**Synthesis (TT corner: 1.2 V, 25°C)**

| Metric | Value |
|---|---|
| Total cells | 45,120 |
| RAM cells (FF-based) | 33,500 |
| Logic cells | 11,620 |
| Total area | 854,844 µm² |
| Logic-only area | 178,473 µm² |
| Post-synthesis WNS | +472 ps ✓ |

**Timing Closure at 25 MHz**

| Stage | WNS | Corner | Status |
|---|---|---|---|
| Post-synthesis | +472 ps | TT, 1.2 V, 25°C | MET ✓ |
| Pre-CTS | −13.1 ns | SS, 1.08 V, 125°C | Expected |
| Post-CTS | +6 ps | SS, 1.08 V, 125°C | MET ✓ |

**Post-Route Power (SS corner: 1.08 V, 125°C)**

| Component | Power (mW) | Share (%) |
|---|---|---|
| Sequential (registers) | 8.312 | 47.1 |
| Combinational (logic) | 7.434 | 42.1 |
| Clock tree | 1.908 | 10.8 |
| **Total** | **17.653** | **100** |

**P&R Summary:** Die 1700×1700 µm · Core 1276×1276 µm · ~52% utilisation · 5 metal layers (M1–M5) · **0 DRC violations** · GDS exported ✓

---

### Comparison with Reference (Fritzmann & Sepulveda, IEEE HOST 2019)

| Metric | Paper [1] | This Work |
|---|---|---|
| FPGA device | Zynq-7000 (Zedboard) | Zynq-7020 |
| FPGA LUTs | 980 | 1,221 |
| FPGA DSPs | 26 | 25 |
| ASIC technology | UMC 65 nm | UMC 130 nm |
| ASIC frequency | 25 MHz | 25 MHz |
| Total cells | 14,352 | 45,120 |
| Total area (µm²) | 329,598 | 854,844 |
| Logic-only area (µm²) | ~300,000 | 178,473 |
| RAM type | SRAM macro | FF-based (no macro in PDK) |
| P_static | 19.2 µW | 0.797 mW |
| P_dynamic | 2.920 mW | 16.856 mW |
| P_total | 2.940 mW | 17.653 mW |

The 2.6× area difference is explained by the 130→65 nm node ratio (~4× gate scaling) and the FF-based RAM (676,371 µm²) substituting the unavailable SRAM macro. Logic-only area scaled to 65 nm gives ~44,618 µm², consistent with the reference datapath. Higher dynamic power reflects greater gate capacitance at 130 nm and FF switching overhead.

---

## Verification

Correctness was verified at two levels:

- **Python reference model:** Cycle-accurate model implementing all algorithms (bit-reversal, LUT twiddle scheduling, Montgomery domain transitions, α-scaling). Round-trip `INTT(NTT(a)) = a` verified for all three parameter sets.
- **Vivado behavioural simulation:** RTL testbench performing forward NTT (compared against Python golden output) and full round-trip across all parameter sets. Verified waveform-by-waveform for the n=8 debug configuration.

---

## Repository Structure

```
.
├── rtl/                    # Synthesisable Verilog-2005 RTL
│   ├── ntt_core.v          # Top-level NTT/INTT core (12-state FSM)
│   ├── ntt_ram.v           # Single-port RAM (n/2 × 32 bits)
│   ├── omega_lut.v         # Twiddle-factor LUT (log₂n + 1 entries)
│   ├── montgomery_reduce.v # Montgomery reduction (5 instances)
│   ├── barrett_reduce.v    # Barrett reduction (2 instances)
│   └── omega_alpha_update.v# ω/α update unit
├── tb/                     # Testbenches
│   └── ntt_tb.v            # Parameterised Vivado testbench
├── model/                  # Python cycle-accurate reference model
│   └── ntt_ref.py
├── fpga/                   # Vivado project constraints and scripts
├── asic/                   # Cadence Genus/Innovus scripts
│   ├── genus_synth.tcl
│   └── innovus_pnr.tcl
├── docs/
│   ├── Low_Power_Presentation.pdf
│   ├── Low_Power_Report.pdf
│   └── Low_Power_2_Page_Report.pdf
└── README.md
```

---

## Tools & Technologies

| Category | Tool / Technology |
|---|---|
| RTL language | Verilog-2005 |
| FPGA synthesis & implementation | Xilinx Vivado 2025.2 |
| FPGA target | Zynq-7020 (xc7z020clg484-1) |
| ASIC synthesis | Cadence Genus v20.11 |
| ASIC place & route | Cadence Innovus v20.14 |
| ASIC technology | UMC 130 nm FSC0H standard cell library |
| Verification model | Python 3 |
| Power analysis (FPGA) | Vivado Power Analysis (SAIF-annotated) |
| Power analysis (ASIC) | Innovus static power (SS corner) |

---

## Key Takeaways

- Polynomial multiplication complexity reduced from **O(n²) → O(n log n)** using NTT
- Complete RTL-to-GDS flow achieved with **zero DRC violations** at 25 MHz, SS worst-case
- **>30% dynamic power reduction** through clock gating and operand isolation
- Single unified datapath supports **all three PQC parameter sets** without re-synthesis
- INTT post-processing folded into the last round saves **at least 2n clock cycles**
- ~75% of the reference paper implemented (side-channel countermeasures excluded)

---

## References

1. T. Fritzmann and J. Sepulveda, "Efficient and Flexible Low-Power NTT for Lattice-Based Cryptography," *Proc. IEEE HOST*, 2019, pp. 141–150.
2. P. L. Montgomery, "Modular Multiplication Without Trial Division," *Mathematics of Computation*, vol. 44, no. 170, pp. 519–521, 1985.
3. J. W. Cooley and J. W. Tukey, "An Algorithm for the Machine Calculation of Complex Fourier Series," *Mathematics of Computation*, vol. 19, no. 90, pp. 297–301, 1965.
4. R. Avanzi et al., "CRYSTALS-Kyber Algorithm Specifications," NIST PQC Round 3 Submission, 2021.
5. E. Alkim et al., "NewHope: A Post-Quantum Key Encapsulation Mechanism," *IACR TCHES*, vol. 2019, no. 3, pp. 514–536, 2019.

---

*IIT Mandi · School of Computing and Electrical Engineering · EE593: Low Power VLSI Design*
