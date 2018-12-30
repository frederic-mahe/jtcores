/*  This file is part of JT_GNG.
    JT_GNG program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT_GNG program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT_GNG.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 27-10-2017 */
    
`timescale 1ns/1ps

module jtgng_colmix(
    input           rst,
    input           clk,    // 24 MHz
    // Synchronization
    //input [2:0]       H,
    // characters
    input [1:0]     chr_col,
    input [3:0]     chr_pal,        // character color code
    // scroll
    input [2:0]     scr_col,
    input [2:0]     scr_pal,
    input           scrwin,
    // objects
    input [5:0]     obj_pxl,
    // Debug
    input           enable_char,
    input           enable_obj,
    input           enable_scr,
    // CPU inteface
    input [7:0]     AB,
    input           blue_cs,
    input           redgreen_cs,
    input [7:0]     DB,
    input           LVBL,
    input           LHBL,   

    output  reg [3:0]   red,
    output  reg [3:0]   green,
    output  reg [3:0]   blue
);

reg addr_top;
reg aux, we;
wire [7:0] dout;

//wire [7:0] pixel_mux = { 2'b11, chr_pal, chr_col };

//reg char_win, scr_win, obj_win;
`ifdef OBJTEST
wire [7:0] pixel_mux = {2'b01,obj_pxl};
`else
reg [7:0] pixel_mux;
always @(*) begin   
    if( chr_col==2'b11 || !enable_char ) begin
        // Object or scroll
        if( enable_scr && &obj_pxl[3:0] || !enable_obj || (scrwin&&scr_col!=3'd0) ) 
            pixel_mux = {2'b00, scr_pal, scr_col }; // scroll wins
        else
            pixel_mux = {2'b01, obj_pxl }; // object wins
        //{ char_win, scr_win, obj_win } = 3'b010;
    end
    else begin // characters
        pixel_mux = { 2'b11, chr_pal, chr_col };
        //{ char_win, scr_win } = 2'b10;
    end
end
`endif

reg [3:0] aux_red, aux_green, aux_blue;

always @(posedge clk)
    if( rst ) begin
        { addr_top, aux } <= 2'b00;
    end else begin
        {addr_top,aux}<={addr_top,aux}+2'b1;
        case( {addr_top,aux} )
            2'b00: we <= redgreen_cs && !LVBL;
            2'b10: we <= blue_cs && !LVBL;
            default: we <= 1'b0;
        endcase
        // assign current pixel colour
        if( LVBL && LHBL )
            case( {addr_top,aux} )
                2'b01: begin
                    red   <= dout[7:4];
                    green <= dout[3:0];
                    end
                2'b11: begin
                    blue  <= dout[7:4];
                    end
                default:;
            endcase // {addr_top,aux}
        else
            {red, green, blue } <= 12'd0; 
    end

wire [8:0] rdaddress = {addr_top, pixel_mux};
wire [8:0] wraddress = {addr_top, AB };

// RAM
jtgng_dual_ram #(.aw(9)) RAM(
    .clk        ( clk       ),
    .clk_en     ( 1'b1      ),
    .data       ( DB        ),
    .rd_addr    ( rdaddress ),
    .wr_addr    ( wraddress ),
    .we         ( we        ),
    .q          ( dout      )
);

endmodule // jtgng_colmix