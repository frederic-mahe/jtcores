/*  This file is part of JTCONTRA.
    JTCONTRA program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCONTRA program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCONTRA.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 1-2-2023 */

module jtcastle_sound(
    input           clk,        // 24 MHz
    input           rst,
    input   [ 1:0]  fxlevel,
    // communication with main CPU
    input           snd_irq,
    input   [ 7:0]  snd_latch,
    // ROM
    output  [14:0]  rom_addr,
    output  reg     rom_cs,
    input   [ 7:0]  rom_data,
    input           rom_ok,
    // ADPCM ROM
    output   [18:0] pcma_addr,
    input    [ 7:0] pcma_dout,
    output          pcma_cs,
    input           pcma_ok,

    output   [18:0] pcmb_addr,
    input    [ 7:0] pcmb_dout,
    output          pcmb_cs,
    input           pcmb_ok,

    // Sound output
    output signed [15:0] snd,
    output               sample,
    output               peak
);
`ifndef NOSOUND
wire        [ 7:0]  cpu_dout, ram_dout, fm_dout, scc_dout;
wire        [15:0]  A;
reg         [ 7:0]  cpu_din;
reg         [ 3:0]  banks;
wire                m1_n, mreq_n, rd_n, wr_n, int_n, nmi_n, iorq_n, rfsh_n;
reg                 ram_cs, latch_cs, fm_cs, scc_cs, dac_cs, bank_cs;
wire signed [15:0]  snd_fm;
wire                cen_fm, cen_fm2;
wire                cpu_cen, irq_ack;
reg                 mem_acc, mem_upper;
wire        [ 7:0]  div_dout;
wire signed [11:0]  pcm_snd;
wire signed [10:0]  scc_snd;

assign rom_addr  = A[14:0];
assign irq_ack   = !m1_n && !iorq_n;

// This connection is done through the NE output
// of the 007232 on the board by using a latch
// and a mux. I can simplify it here:
assign pcma_addr[18:17] = banks[1:0];
assign pcmb_addr[18:17] = banks[3:2];

jtframe_cen3p57 #(.CLK24(1)) u_cen(
    .clk        ( clk       ),
    .cen_3p57   ( cen_fm    ),
    .cen_1p78   ( cen_fm2   )
);

always @(*) begin
    mem_acc  = !mreq_n && rfsh_n;
    rom_cs   = mem_acc && !A[15] && !rd_n;
    // Devices
    mem_upper = mem_acc && A[15];
    ram_cs    = mem_upper && A[14:12]==0; // 8xxx
    scc_cs    = mem_upper && A[14:12]==1; // 9xxx - 051649
    fm_cs     = mem_upper && A[14:12]==2; // Axxx
    dac_cs    = mem_upper && A[14:12]==3; // Bxxx
    bank_cs   = mem_upper && A[14:12]==6; // Cxxx
    latch_cs  = mem_upper && A[14:12]==6; // Dxxx

end

always @(*) begin
    case(1'b1)
        rom_cs:      cpu_din = rom_data;
        ram_cs:      cpu_din = ram_dout;
        scc_cs:      cpu_din = scc_dout;
        latch_cs:    cpu_din = snd_latch;
        fm_cs:       cpu_din = fm_dout;
        default:     cpu_din = 8'hff;
    endcase
end

reg [7:0] fxgain;

always @(*) begin
    case( fxlevel )
        0: fxgain = 8'h02;
        1: fxgain = 8'h04;
        2: fxgain = 8'h08;
        3: fxgain = 8'h10;
    endcase
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        banks <= 0;
    end else begin
        if( bank_cs ) banks <= cpu_dout[3:0];
    end
end

jtframe_mixer #(.W0(16),.W1(11),.W2(12)) u_mixer(
    .rst    ( rst        ),
    .clk    ( clk        ),
    .cen    ( cen_fm     ),
    .ch0    ( snd_fm     ),
    .ch1    ( scc_snd    ),
    .ch2    ( pcm_snd    ),
    .ch3    ( 16'd0      ),
    .gain0  ( 8'h08      ),
    .gain1  ( 8'h08      ),
    .gain2  ( fxgain     ),
    .gain3  ( 8'd0       ),
    .mixed  ( snd        ),
    .peak   ( peak       )
);

jtframe_ff u_ff(
    .clk      ( clk         ),
    .rst      ( rst         ),
    .cen      ( 1'b1        ),
    .din      ( 1'b1        ),
    .q        (             ),
    .qn       ( int_n       ),
    .set      ( 1'b0        ),    // active high
    .clr      ( irq_ack     ),    // active high
    .sigedge  ( snd_irq     ) // signal whose edge will trigger the FF
);

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .cpu_cen    ( cpu_cen   ),
    .int_n      ( int_n     ),
    .nmi_n      ( nmi_n     ),
    .busrq_n    ( 1'b1      ),
    .m1_n       ( m1_n      ),
    .mreq_n     ( mreq_n    ),
    .iorq_n     ( iorq_n    ),
    .rd_n       ( rd_n      ),
    .wr_n       ( wr_n      ),
    .rfsh_n     ( rfsh_n    ),
    .halt_n     (           ),
    .busak_n    (           ),
    .A          ( A         ),
    .cpu_din    ( cpu_din   ),
    .cpu_dout   ( cpu_dout  ),
    .ram_dout   ( ram_dout  ),
    // ROM access
    .ram_cs     ( ram_cs    ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    )
);

jtopl u_opl(
    .rst        ( rst       ), // reset
    .clk        ( clk       ), // main clock
    .cen        ( cen_fm    ),
    .addr       ( A[0]      ),
    .din        ( cpu_dout  ), // data in
    .dout       ( fm_dout   ), // data out
    .cs_n       ( !fm_cs    ), // chip select
    .wr_n       ( wr_n      ), // write
    .irq_n      ( nmi_n     ),
    // combined output
    .snd        ( snd_fm    ),
    .sample     ( sample    ), // marks new output sample
);

jt007232 u_pcm(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .addr       ( A[3:0]    ),
    .dacs       ( dac_cs    ), // active high
    .cen_q      (           ),
    .cen_e      (           ),
    .wr_n       ( wr_n      ),
    .din        ( cpu_dout  ),

    // External memory - the original chip
    // only had one bus
    .roma_addr  ( pcma_addr[16:0] ),
    .roma_dout  ( pcma_dout ),
    .roma_cs    ( pcma_cs   ),
    .roma_ok    ( pcma_ok   ),

    .romb_addr  ( pcmb_addr[16:0] ),
    .romb_dout  ( pcmb_dout ),
    .romb_cs    ( pcmb_cs   ),
    .romb_ok    ( pcmb_ok   ),
    // sound output - raw
    .snda       (           ),
    .sndb       (           ),
    .snd        ( pcm_snd   )
);

jt051649 u_scc(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen_fm    ),
    .cs         ( scc_cs    ),
    .wrn        ( wr_n      ),
    .addr       ( {4'b1001, cpu_addr[11:0] }), // bits 10-8 ignored
    .din        ( cpu_din   ),
    .dout       ( scc_dout  ),
    .snd        ( scc_snd   )
);

`else
assign rom_cs   = 0;
assign pcm_cs   = 0;
assign rom_addr = 15'd0;
assign snd      = 0;
assign peak     = 0;
assign sample   = 0;
`endif
endmodule
