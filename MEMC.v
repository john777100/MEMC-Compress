`define PIXEL_NUM 2448 // 48*51=2448
module MEMC(
    clk,
    rst_n,
    pixel_valid,
    pixel,
    busy,
    mv_valid,
    mv,
    mv_addr
);

input clk;
input rst_n;
input pixel_valid;
input [7:0] pixel;
output busy;
output mv_valid;
output [7:0] mv;
output [5:0] mv_addr;

assign busy = 1'b0;
// buffer input
reg buf_pixel_valid;
reg [2:0] buf_pixel;
always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        buf_pixel_valid <= 1'b0;
        buf_pixel <= 0;
    end
    else begin
        buf_pixel_valid <= pixel_valid;
        buf_pixel <= pixel[7:5];
    end
end
localparam IDLE = 2'b00;
localparam INPUT_START = 2'b01;
localparam OUTPUT_START = 2'b11;

reg [1:0] state, n_state;
reg mv_valid, n_mv_valid;
reg [1:0] mv_col, n_mv_col;
reg [5:0] mv_addr, n_mv_addr;
// we tie mv_row to be always zero and mv_col be fixed in -2~1 (2 bits)
assign mv = {4'b0000, {2{mv_col[1]}}, mv_col};

// 48*51=2448
reg [2:0] base_frame [0:`PIXEL_NUM-1];
reg [2:0] n_base_frame [0:`PIXEL_NUM-1];
reg [3:0] frame_count, n_frame_count; // this count 0~9 for 10 frames
reg [5:0] pixel_col_count, n_pixel_col_count; // this count 0~63 for col pixels
reg [5:0] pixel_row_count, n_pixel_row_count; // this count 0~47 for row pixels

reg [7:0] SAD [1:6][0:3];
reg [7:0] n_SAD [1:6][0:3];
wire [3:0] temp_diff [0:3];
wire [2:0] abs_diff [0:3];
reg [7:0] best_SAD, n_best_SAD;

assign temp_diff[2] = {1'b0, buf_pixel} - {1'b0, base_frame[0]};
assign temp_diff[3] = {1'b0, buf_pixel} - {1'b0, base_frame[1]};
assign temp_diff[0] = {1'b0, buf_pixel} - {1'b0, base_frame[2]};
assign temp_diff[1] = {1'b0, buf_pixel} - {1'b0, base_frame[3]};
assign abs_diff[2] = temp_diff[2][3] ? ~temp_diff[2][2:0]+1 : temp_diff[2][2:0];
assign abs_diff[3] = temp_diff[3][3] ? ~temp_diff[3][2:0]+1 : temp_diff[3][2:0];
assign abs_diff[0] = temp_diff[0][3] ? ~temp_diff[0][2:0]+1 : temp_diff[0][2:0];
assign abs_diff[1] = temp_diff[1][3] ? ~temp_diff[1][2:0]+1 : temp_diff[1][2:0];

// control signals: state and counters
always @ (*) begin
    n_state = state;
    case (state)
        IDLE: begin
            if (buf_pixel_valid) begin
                n_state = INPUT_START;
            end
        end
        INPUT_START: begin
            // upon a block is done (row_count=8n+7, col_count=8n+7)
            if (frame_count && &pixel_row_count[2:0] && &pixel_col_count[2:0]) begin
                n_state = OUTPUT_START;
            end
        end
        OUTPUT_START: begin
            // col_count 0,1,2 for comparision of SAD, 3 for output, 4 for update base_frame
            if (pixel_col_count[2]) begin
                n_state = INPUT_START;
            end
        end
    endcase
    n_frame_count = frame_count;
    n_pixel_col_count = pixel_col_count;
    n_pixel_row_count = pixel_row_count;
    if (state[0]) begin
        n_pixel_col_count = pixel_col_count + 1;
        if (pixel_col_count == 6'd63) begin
            n_pixel_col_count = 6'd0;
            n_pixel_row_count = pixel_row_count + 1;
            if (pixel_row_count == 6'd47) begin
                n_pixel_col_count = 0;
                n_pixel_row_count = 0;
                n_frame_count = frame_count + 1;
            end
        end
    end
end

// SAD comparison
always@(*) begin
    n_best_SAD = best_SAD;
    n_mv_col = mv_col;
    case (pixel_col_count[5:3])
        0: n_mv_col = 0;
        1: n_mv_col = 0;
        2: begin
            case (pixel_col_count[2:0])
                0: begin
                    if (SAD[1][2] > SAD[1][3]) begin
                        n_best_SAD = SAD[1][3];
                        n_mv_col = 2'b11;
                    end
                    else begin
                        n_best_SAD = SAD[1][2];
                        n_mv_col = 2'b10;
                    end
                end
                1: begin
                    if (best_SAD > SAD[1][0]) begin
                        n_best_SAD = SAD[1][0];
                        n_mv_col = 2'b00;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
                2: begin
                    if (best_SAD > SAD[1][1]) begin
                        n_best_SAD = SAD[1][1];
                        n_mv_col = 2'b01;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
            endcase
        end
        3: begin
            case (pixel_col_count[2:0])
                0: begin
                    if (SAD[2][2] > SAD[2][3]) begin
                        n_best_SAD = SAD[2][3];
                        n_mv_col = 2'b11;
                    end
                    else begin
                        n_best_SAD = SAD[2][2];
                        n_mv_col = 2'b10;
                    end
                end
                1: begin
                    if (best_SAD > SAD[2][0]) begin
                        n_best_SAD = SAD[2][0];
                        n_mv_col = 2'b00;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
                2: begin
                    if (best_SAD > SAD[2][1]) begin
                        n_best_SAD = SAD[2][1];
                        n_mv_col = 2'b01;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
            endcase
        end
        4: begin
            case (pixel_col_count[2:0])
                0: begin
                    if (SAD[3][2] > SAD[3][3]) begin
                        n_best_SAD = SAD[3][3];
                        n_mv_col = 2'b11;
                    end
                    else begin
                        n_best_SAD = SAD[3][2];
                        n_mv_col = 2'b10;
                    end
                end
                1: begin
                    if (best_SAD > SAD[3][0]) begin
                        n_best_SAD = SAD[3][0];
                        n_mv_col = 2'b00;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
                2: begin
                    if (best_SAD > SAD[3][1]) begin
                        n_best_SAD = SAD[3][1];
                        n_mv_col = 2'b01;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
            endcase
        end
        5: begin
            case (pixel_col_count[2:0])
                0: begin
                    if (SAD[4][2] > SAD[4][3]) begin
                        n_best_SAD = SAD[4][3];
                        n_mv_col = 2'b11;
                    end
                    else begin
                        n_best_SAD = SAD[4][2];
                        n_mv_col = 2'b10;
                    end
                end
                1: begin
                    if (best_SAD > SAD[4][0]) begin
                        n_best_SAD = SAD[4][0];
                        n_mv_col = 2'b00;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
                2: begin
                    if (best_SAD > SAD[4][1]) begin
                        n_best_SAD = SAD[4][1];
                        n_mv_col = 2'b01;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
            endcase
        end
        6: begin
            case (pixel_col_count[2:0])
                0: begin
                    if (SAD[5][2] > SAD[5][3]) begin
                        n_best_SAD = SAD[5][3];
                        n_mv_col = 2'b11;
                    end
                    else begin
                        n_best_SAD = SAD[5][2];
                        n_mv_col = 2'b10;
                    end
                end
                1: begin
                    if (best_SAD > SAD[5][0]) begin
                        n_best_SAD = SAD[5][0];
                        n_mv_col = 2'b00;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
                2: begin
                    if (best_SAD > SAD[5][1]) begin
                        n_best_SAD = SAD[5][1];
                        n_mv_col = 2'b01;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
            endcase
        end
        7: begin
            case (pixel_col_count[2:0])
                0: begin
                    if (SAD[6][2] > SAD[6][3]) begin
                        n_best_SAD = SAD[6][3];
                        n_mv_col = 2'b11;
                    end
                    else begin
                        n_best_SAD = SAD[6][2];
                        n_mv_col = 2'b10;
                    end
                end
                1: begin
                    if (best_SAD > SAD[6][0]) begin
                        n_best_SAD = SAD[6][0];
                        n_mv_col = 2'b00;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
                2: begin
                    if (best_SAD > SAD[6][1]) begin
                        n_best_SAD = SAD[6][1];
                        n_mv_col = 2'b01;
                    end
                    else begin
                        n_best_SAD = best_SAD;
                        n_mv_col = mv_col;
                    end
                end
            endcase
        end
    endcase
end

integer i, j, k;
// for input and base_frame update
always @(*) begin
    for (i=0;i<`PIXEL_NUM;i=i+1) begin
        n_base_frame[i] = base_frame[i];
    end
    for (j=1;j<=6;j=j+1) begin
        for (k=0;k<4;k=k+1) begin
            n_SAD[j][k] = SAD[j][k];
        end
    end
    if (state[0]) begin
        if (frame_count) begin
            case (pixel_col_count[5:3])
                3'd1: begin
                    n_SAD[1][2] = SAD[1][2] + abs_diff[2];
                    n_SAD[1][3] = SAD[1][3] + abs_diff[3];
                    n_SAD[1][0] = SAD[1][0] + abs_diff[0];
                    n_SAD[1][1] = SAD[1][1] + abs_diff[1];
                end
                3'd2: begin
                    n_SAD[2][2] = SAD[2][2] + abs_diff[2];
                    n_SAD[2][3] = SAD[2][3] + abs_diff[3];
                    n_SAD[2][0] = SAD[2][0] + abs_diff[0];
                    n_SAD[2][1] = SAD[2][1] + abs_diff[1];
                end
                3'd3: begin
                    n_SAD[3][2] = SAD[3][2] + abs_diff[2];
                    n_SAD[3][3] = SAD[3][3] + abs_diff[3];
                    n_SAD[3][0] = SAD[3][0] + abs_diff[0];
                    n_SAD[3][1] = SAD[3][1] + abs_diff[1];
                end
                3'd4: begin
                    n_SAD[4][2] = SAD[4][2] + abs_diff[2];
                    n_SAD[4][3] = SAD[4][3] + abs_diff[3];
                    n_SAD[4][0] = SAD[4][0] + abs_diff[0];
                    n_SAD[4][1] = SAD[4][1] + abs_diff[1];
                end
                3'd5: begin
                    n_SAD[5][2] = SAD[5][2] + abs_diff[2];
                    n_SAD[5][3] = SAD[5][3] + abs_diff[3];
                    n_SAD[5][0] = SAD[5][0] + abs_diff[0];
                    n_SAD[5][1] = SAD[5][1] + abs_diff[1];
                end
                3'd6: begin
                    n_SAD[6][2] = SAD[6][2] + abs_diff[2];
                    n_SAD[6][3] = SAD[6][3] + abs_diff[3];
                    n_SAD[6][0] = SAD[6][0] + abs_diff[0];
                    n_SAD[6][1] = SAD[6][1] + abs_diff[1];
                end
            endcase
            if (!pixel_row_count[2:0] && !pixel_col_count[5:3]) begin
                n_SAD[1][2] = 0;
                n_SAD[1][3] = 0;
                n_SAD[1][0] = 0;
                n_SAD[1][1] = 0;
                n_SAD[2][2] = 0;
                n_SAD[2][3] = 0;
                n_SAD[2][0] = 0;
                n_SAD[2][1] = 0;
                n_SAD[3][2] = 0;
                n_SAD[3][3] = 0;
                n_SAD[3][0] = 0;
                n_SAD[3][1] = 0;
                n_SAD[4][2] = 0;
                n_SAD[4][3] = 0;
                n_SAD[4][0] = 0;
                n_SAD[4][1] = 0;
                n_SAD[5][2] = 0;
                n_SAD[5][3] = 0;
                n_SAD[5][0] = 0;
                n_SAD[5][1] = 0;
                n_SAD[6][2] = 0;
                n_SAD[6][3] = 0;
                n_SAD[6][0] = 0;
                n_SAD[6][1] = 0;
            end
            if (pixel_col_count >= 8 && pixel_col_count <= 58) begin
                n_base_frame[`PIXEL_NUM-1] = base_frame[0];
                for (i=0;i<`PIXEL_NUM-1;i=i+1) begin
                    n_base_frame[i] = base_frame[i+1];
                end
                if (state[1] && pixel_col_count[2]) begin
                    case (mv_col)
                        2'b01: begin // +1
                            n_base_frame[`PIXEL_NUM-4]   = base_frame[`PIXEL_NUM-2];
                            n_base_frame[`PIXEL_NUM-5]   = base_frame[`PIXEL_NUM-3];
                            n_base_frame[`PIXEL_NUM-6]   = base_frame[`PIXEL_NUM-4];
                            n_base_frame[`PIXEL_NUM-7]   = base_frame[`PIXEL_NUM-5];
                            n_base_frame[`PIXEL_NUM-8]   = base_frame[`PIXEL_NUM-6];
                            n_base_frame[`PIXEL_NUM-9]   = base_frame[`PIXEL_NUM-7];
                            n_base_frame[`PIXEL_NUM-10]  = base_frame[`PIXEL_NUM-8];
                            n_base_frame[`PIXEL_NUM-11]  = base_frame[`PIXEL_NUM-9];
                            n_base_frame[`PIXEL_NUM-55]  = base_frame[`PIXEL_NUM-53];
                            n_base_frame[`PIXEL_NUM-56]  = base_frame[`PIXEL_NUM-54];
                            n_base_frame[`PIXEL_NUM-57]  = base_frame[`PIXEL_NUM-55];
                            n_base_frame[`PIXEL_NUM-58]  = base_frame[`PIXEL_NUM-56];
                            n_base_frame[`PIXEL_NUM-59]  = base_frame[`PIXEL_NUM-57];
                            n_base_frame[`PIXEL_NUM-60]  = base_frame[`PIXEL_NUM-58];
                            n_base_frame[`PIXEL_NUM-61]  = base_frame[`PIXEL_NUM-59];
                            n_base_frame[`PIXEL_NUM-62]  = base_frame[`PIXEL_NUM-60];
                            n_base_frame[`PIXEL_NUM-106] = base_frame[`PIXEL_NUM-104];
                            n_base_frame[`PIXEL_NUM-107] = base_frame[`PIXEL_NUM-105];
                            n_base_frame[`PIXEL_NUM-108] = base_frame[`PIXEL_NUM-106];
                            n_base_frame[`PIXEL_NUM-109] = base_frame[`PIXEL_NUM-107];
                            n_base_frame[`PIXEL_NUM-110] = base_frame[`PIXEL_NUM-108];
                            n_base_frame[`PIXEL_NUM-111] = base_frame[`PIXEL_NUM-109];
                            n_base_frame[`PIXEL_NUM-112] = base_frame[`PIXEL_NUM-110];
                            n_base_frame[`PIXEL_NUM-113] = base_frame[`PIXEL_NUM-111];
                            n_base_frame[`PIXEL_NUM-157] = base_frame[`PIXEL_NUM-155];
                            n_base_frame[`PIXEL_NUM-158] = base_frame[`PIXEL_NUM-156];
                            n_base_frame[`PIXEL_NUM-159] = base_frame[`PIXEL_NUM-157];
                            n_base_frame[`PIXEL_NUM-160] = base_frame[`PIXEL_NUM-158];
                            n_base_frame[`PIXEL_NUM-161] = base_frame[`PIXEL_NUM-159];
                            n_base_frame[`PIXEL_NUM-162] = base_frame[`PIXEL_NUM-160];
                            n_base_frame[`PIXEL_NUM-163] = base_frame[`PIXEL_NUM-161];
                            n_base_frame[`PIXEL_NUM-164] = base_frame[`PIXEL_NUM-162];
                            n_base_frame[`PIXEL_NUM-208] = base_frame[`PIXEL_NUM-206];
                            n_base_frame[`PIXEL_NUM-209] = base_frame[`PIXEL_NUM-207];
                            n_base_frame[`PIXEL_NUM-210] = base_frame[`PIXEL_NUM-208];
                            n_base_frame[`PIXEL_NUM-211] = base_frame[`PIXEL_NUM-209];
                            n_base_frame[`PIXEL_NUM-212] = base_frame[`PIXEL_NUM-210];
                            n_base_frame[`PIXEL_NUM-213] = base_frame[`PIXEL_NUM-211];
                            n_base_frame[`PIXEL_NUM-214] = base_frame[`PIXEL_NUM-212];
                            n_base_frame[`PIXEL_NUM-215] = base_frame[`PIXEL_NUM-213];
                            n_base_frame[`PIXEL_NUM-259] = base_frame[`PIXEL_NUM-257];
                            n_base_frame[`PIXEL_NUM-260] = base_frame[`PIXEL_NUM-258];
                            n_base_frame[`PIXEL_NUM-261] = base_frame[`PIXEL_NUM-259];
                            n_base_frame[`PIXEL_NUM-262] = base_frame[`PIXEL_NUM-260];
                            n_base_frame[`PIXEL_NUM-263] = base_frame[`PIXEL_NUM-261];
                            n_base_frame[`PIXEL_NUM-264] = base_frame[`PIXEL_NUM-262];
                            n_base_frame[`PIXEL_NUM-265] = base_frame[`PIXEL_NUM-263];
                            n_base_frame[`PIXEL_NUM-266] = base_frame[`PIXEL_NUM-264];
                            n_base_frame[`PIXEL_NUM-310] = base_frame[`PIXEL_NUM-308];
                            n_base_frame[`PIXEL_NUM-311] = base_frame[`PIXEL_NUM-309];
                            n_base_frame[`PIXEL_NUM-312] = base_frame[`PIXEL_NUM-310];
                            n_base_frame[`PIXEL_NUM-313] = base_frame[`PIXEL_NUM-311];
                            n_base_frame[`PIXEL_NUM-314] = base_frame[`PIXEL_NUM-312];
                            n_base_frame[`PIXEL_NUM-315] = base_frame[`PIXEL_NUM-313];
                            n_base_frame[`PIXEL_NUM-316] = base_frame[`PIXEL_NUM-314];
                            n_base_frame[`PIXEL_NUM-317] = base_frame[`PIXEL_NUM-315];
                            n_base_frame[`PIXEL_NUM-361] = base_frame[`PIXEL_NUM-359];
                            n_base_frame[`PIXEL_NUM-362] = base_frame[`PIXEL_NUM-360];
                            n_base_frame[`PIXEL_NUM-363] = base_frame[`PIXEL_NUM-361];
                            n_base_frame[`PIXEL_NUM-364] = base_frame[`PIXEL_NUM-362];
                            n_base_frame[`PIXEL_NUM-365] = base_frame[`PIXEL_NUM-363];
                            n_base_frame[`PIXEL_NUM-366] = base_frame[`PIXEL_NUM-364];
                            n_base_frame[`PIXEL_NUM-367] = base_frame[`PIXEL_NUM-365];
                            n_base_frame[`PIXEL_NUM-368] = base_frame[`PIXEL_NUM-366];
                        end
                        2'b11: begin // -1
                            n_base_frame[`PIXEL_NUM-4]   = base_frame[`PIXEL_NUM-4];
                            n_base_frame[`PIXEL_NUM-5]   = base_frame[`PIXEL_NUM-5];
                            n_base_frame[`PIXEL_NUM-6]   = base_frame[`PIXEL_NUM-6];
                            n_base_frame[`PIXEL_NUM-7]   = base_frame[`PIXEL_NUM-7];
                            n_base_frame[`PIXEL_NUM-8]   = base_frame[`PIXEL_NUM-8];
                            n_base_frame[`PIXEL_NUM-9]   = base_frame[`PIXEL_NUM-9];
                            n_base_frame[`PIXEL_NUM-10]  = base_frame[`PIXEL_NUM-10];
                            n_base_frame[`PIXEL_NUM-11]  = base_frame[`PIXEL_NUM-11];
                            n_base_frame[`PIXEL_NUM-55]  = base_frame[`PIXEL_NUM-55];
                            n_base_frame[`PIXEL_NUM-56]  = base_frame[`PIXEL_NUM-56];
                            n_base_frame[`PIXEL_NUM-57]  = base_frame[`PIXEL_NUM-57];
                            n_base_frame[`PIXEL_NUM-58]  = base_frame[`PIXEL_NUM-58];
                            n_base_frame[`PIXEL_NUM-59]  = base_frame[`PIXEL_NUM-59];
                            n_base_frame[`PIXEL_NUM-60]  = base_frame[`PIXEL_NUM-60];
                            n_base_frame[`PIXEL_NUM-61]  = base_frame[`PIXEL_NUM-61];
                            n_base_frame[`PIXEL_NUM-62]  = base_frame[`PIXEL_NUM-62];
                            n_base_frame[`PIXEL_NUM-106] = base_frame[`PIXEL_NUM-106];
                            n_base_frame[`PIXEL_NUM-107] = base_frame[`PIXEL_NUM-107];
                            n_base_frame[`PIXEL_NUM-108] = base_frame[`PIXEL_NUM-108];
                            n_base_frame[`PIXEL_NUM-109] = base_frame[`PIXEL_NUM-109];
                            n_base_frame[`PIXEL_NUM-110] = base_frame[`PIXEL_NUM-110];
                            n_base_frame[`PIXEL_NUM-111] = base_frame[`PIXEL_NUM-111];
                            n_base_frame[`PIXEL_NUM-112] = base_frame[`PIXEL_NUM-112];
                            n_base_frame[`PIXEL_NUM-113] = base_frame[`PIXEL_NUM-113];
                            n_base_frame[`PIXEL_NUM-157] = base_frame[`PIXEL_NUM-157];
                            n_base_frame[`PIXEL_NUM-158] = base_frame[`PIXEL_NUM-158];
                            n_base_frame[`PIXEL_NUM-159] = base_frame[`PIXEL_NUM-159];
                            n_base_frame[`PIXEL_NUM-160] = base_frame[`PIXEL_NUM-160];
                            n_base_frame[`PIXEL_NUM-161] = base_frame[`PIXEL_NUM-161];
                            n_base_frame[`PIXEL_NUM-162] = base_frame[`PIXEL_NUM-162];
                            n_base_frame[`PIXEL_NUM-163] = base_frame[`PIXEL_NUM-163];
                            n_base_frame[`PIXEL_NUM-164] = base_frame[`PIXEL_NUM-164];
                            n_base_frame[`PIXEL_NUM-208] = base_frame[`PIXEL_NUM-208];
                            n_base_frame[`PIXEL_NUM-209] = base_frame[`PIXEL_NUM-209];
                            n_base_frame[`PIXEL_NUM-210] = base_frame[`PIXEL_NUM-210];
                            n_base_frame[`PIXEL_NUM-211] = base_frame[`PIXEL_NUM-211];
                            n_base_frame[`PIXEL_NUM-212] = base_frame[`PIXEL_NUM-212];
                            n_base_frame[`PIXEL_NUM-213] = base_frame[`PIXEL_NUM-213];
                            n_base_frame[`PIXEL_NUM-214] = base_frame[`PIXEL_NUM-214];
                            n_base_frame[`PIXEL_NUM-215] = base_frame[`PIXEL_NUM-215];
                            n_base_frame[`PIXEL_NUM-259] = base_frame[`PIXEL_NUM-259];
                            n_base_frame[`PIXEL_NUM-260] = base_frame[`PIXEL_NUM-260];
                            n_base_frame[`PIXEL_NUM-261] = base_frame[`PIXEL_NUM-261];
                            n_base_frame[`PIXEL_NUM-262] = base_frame[`PIXEL_NUM-262];
                            n_base_frame[`PIXEL_NUM-263] = base_frame[`PIXEL_NUM-263];
                            n_base_frame[`PIXEL_NUM-264] = base_frame[`PIXEL_NUM-264];
                            n_base_frame[`PIXEL_NUM-265] = base_frame[`PIXEL_NUM-265];
                            n_base_frame[`PIXEL_NUM-266] = base_frame[`PIXEL_NUM-266];
                            n_base_frame[`PIXEL_NUM-310] = base_frame[`PIXEL_NUM-310];
                            n_base_frame[`PIXEL_NUM-311] = base_frame[`PIXEL_NUM-311];
                            n_base_frame[`PIXEL_NUM-312] = base_frame[`PIXEL_NUM-312];
                            n_base_frame[`PIXEL_NUM-313] = base_frame[`PIXEL_NUM-313];
                            n_base_frame[`PIXEL_NUM-314] = base_frame[`PIXEL_NUM-314];
                            n_base_frame[`PIXEL_NUM-315] = base_frame[`PIXEL_NUM-315];
                            n_base_frame[`PIXEL_NUM-316] = base_frame[`PIXEL_NUM-316];
                            n_base_frame[`PIXEL_NUM-317] = base_frame[`PIXEL_NUM-317];
                            n_base_frame[`PIXEL_NUM-361] = base_frame[`PIXEL_NUM-361];
                            n_base_frame[`PIXEL_NUM-362] = base_frame[`PIXEL_NUM-362];
                            n_base_frame[`PIXEL_NUM-363] = base_frame[`PIXEL_NUM-363];
                            n_base_frame[`PIXEL_NUM-364] = base_frame[`PIXEL_NUM-364];
                            n_base_frame[`PIXEL_NUM-365] = base_frame[`PIXEL_NUM-365];
                            n_base_frame[`PIXEL_NUM-366] = base_frame[`PIXEL_NUM-366];
                            n_base_frame[`PIXEL_NUM-367] = base_frame[`PIXEL_NUM-367];
                            n_base_frame[`PIXEL_NUM-368] = base_frame[`PIXEL_NUM-368];
                        end
                        2'b10: begin // -2
                            n_base_frame[`PIXEL_NUM-4]   = base_frame[`PIXEL_NUM-5];
                            n_base_frame[`PIXEL_NUM-5]   = base_frame[`PIXEL_NUM-6];
                            n_base_frame[`PIXEL_NUM-6]   = base_frame[`PIXEL_NUM-7];
                            n_base_frame[`PIXEL_NUM-7]   = base_frame[`PIXEL_NUM-8];
                            n_base_frame[`PIXEL_NUM-8]   = base_frame[`PIXEL_NUM-9];
                            n_base_frame[`PIXEL_NUM-9]   = base_frame[`PIXEL_NUM-10];
                            n_base_frame[`PIXEL_NUM-10]  = base_frame[`PIXEL_NUM-11];
                            n_base_frame[`PIXEL_NUM-11]  = base_frame[`PIXEL_NUM-12];
                            n_base_frame[`PIXEL_NUM-55]  = base_frame[`PIXEL_NUM-56];
                            n_base_frame[`PIXEL_NUM-56]  = base_frame[`PIXEL_NUM-57];
                            n_base_frame[`PIXEL_NUM-57]  = base_frame[`PIXEL_NUM-58];
                            n_base_frame[`PIXEL_NUM-58]  = base_frame[`PIXEL_NUM-59];
                            n_base_frame[`PIXEL_NUM-59]  = base_frame[`PIXEL_NUM-60];
                            n_base_frame[`PIXEL_NUM-60]  = base_frame[`PIXEL_NUM-61];
                            n_base_frame[`PIXEL_NUM-61]  = base_frame[`PIXEL_NUM-62];
                            n_base_frame[`PIXEL_NUM-62]  = base_frame[`PIXEL_NUM-63];
                            n_base_frame[`PIXEL_NUM-106] = base_frame[`PIXEL_NUM-107];
                            n_base_frame[`PIXEL_NUM-107] = base_frame[`PIXEL_NUM-108];
                            n_base_frame[`PIXEL_NUM-108] = base_frame[`PIXEL_NUM-109];
                            n_base_frame[`PIXEL_NUM-109] = base_frame[`PIXEL_NUM-110];
                            n_base_frame[`PIXEL_NUM-110] = base_frame[`PIXEL_NUM-111];
                            n_base_frame[`PIXEL_NUM-111] = base_frame[`PIXEL_NUM-112];
                            n_base_frame[`PIXEL_NUM-112] = base_frame[`PIXEL_NUM-113];
                            n_base_frame[`PIXEL_NUM-113] = base_frame[`PIXEL_NUM-114];
                            n_base_frame[`PIXEL_NUM-157] = base_frame[`PIXEL_NUM-158];
                            n_base_frame[`PIXEL_NUM-158] = base_frame[`PIXEL_NUM-159];
                            n_base_frame[`PIXEL_NUM-159] = base_frame[`PIXEL_NUM-160];
                            n_base_frame[`PIXEL_NUM-160] = base_frame[`PIXEL_NUM-161];
                            n_base_frame[`PIXEL_NUM-161] = base_frame[`PIXEL_NUM-162];
                            n_base_frame[`PIXEL_NUM-162] = base_frame[`PIXEL_NUM-163];
                            n_base_frame[`PIXEL_NUM-163] = base_frame[`PIXEL_NUM-164];
                            n_base_frame[`PIXEL_NUM-164] = base_frame[`PIXEL_NUM-165];
                            n_base_frame[`PIXEL_NUM-208] = base_frame[`PIXEL_NUM-209];
                            n_base_frame[`PIXEL_NUM-209] = base_frame[`PIXEL_NUM-210];
                            n_base_frame[`PIXEL_NUM-210] = base_frame[`PIXEL_NUM-211];
                            n_base_frame[`PIXEL_NUM-211] = base_frame[`PIXEL_NUM-212];
                            n_base_frame[`PIXEL_NUM-212] = base_frame[`PIXEL_NUM-213];
                            n_base_frame[`PIXEL_NUM-213] = base_frame[`PIXEL_NUM-214];
                            n_base_frame[`PIXEL_NUM-214] = base_frame[`PIXEL_NUM-215];
                            n_base_frame[`PIXEL_NUM-215] = base_frame[`PIXEL_NUM-216];
                            n_base_frame[`PIXEL_NUM-259] = base_frame[`PIXEL_NUM-260];
                            n_base_frame[`PIXEL_NUM-260] = base_frame[`PIXEL_NUM-261];
                            n_base_frame[`PIXEL_NUM-261] = base_frame[`PIXEL_NUM-262];
                            n_base_frame[`PIXEL_NUM-262] = base_frame[`PIXEL_NUM-263];
                            n_base_frame[`PIXEL_NUM-263] = base_frame[`PIXEL_NUM-264];
                            n_base_frame[`PIXEL_NUM-264] = base_frame[`PIXEL_NUM-265];
                            n_base_frame[`PIXEL_NUM-265] = base_frame[`PIXEL_NUM-266];
                            n_base_frame[`PIXEL_NUM-266] = base_frame[`PIXEL_NUM-267];
                            n_base_frame[`PIXEL_NUM-310] = base_frame[`PIXEL_NUM-311];
                            n_base_frame[`PIXEL_NUM-311] = base_frame[`PIXEL_NUM-312];
                            n_base_frame[`PIXEL_NUM-312] = base_frame[`PIXEL_NUM-313];
                            n_base_frame[`PIXEL_NUM-313] = base_frame[`PIXEL_NUM-314];
                            n_base_frame[`PIXEL_NUM-314] = base_frame[`PIXEL_NUM-315];
                            n_base_frame[`PIXEL_NUM-315] = base_frame[`PIXEL_NUM-316];
                            n_base_frame[`PIXEL_NUM-316] = base_frame[`PIXEL_NUM-317];
                            n_base_frame[`PIXEL_NUM-317] = base_frame[`PIXEL_NUM-318];
                            n_base_frame[`PIXEL_NUM-361] = base_frame[`PIXEL_NUM-362];
                            n_base_frame[`PIXEL_NUM-362] = base_frame[`PIXEL_NUM-363];
                            n_base_frame[`PIXEL_NUM-363] = base_frame[`PIXEL_NUM-364];
                            n_base_frame[`PIXEL_NUM-364] = base_frame[`PIXEL_NUM-365];
                            n_base_frame[`PIXEL_NUM-365] = base_frame[`PIXEL_NUM-366];
                            n_base_frame[`PIXEL_NUM-366] = base_frame[`PIXEL_NUM-367];
                            n_base_frame[`PIXEL_NUM-367] = base_frame[`PIXEL_NUM-368];
                            n_base_frame[`PIXEL_NUM-368] = base_frame[`PIXEL_NUM-369];
                        end
                    endcase
                end
            end
        end
        else begin
            // store the first frame (frame_count=0) to be the base_frame
            // we don't store the first and the last col block
            if (pixel_col_count >= 6 && pixel_col_count <= 56) begin
                n_base_frame[`PIXEL_NUM-1] = buf_pixel;
                for (i=0;i<`PIXEL_NUM-1;i=i+1) begin
                    n_base_frame[i] = base_frame[i+1];
                end
            end
        end
    end
end

// for output
always @(*) begin
    n_mv_addr = mv_addr;
    n_mv_valid = 1'b0;
    if (state[1]) begin
        if (pixel_col_count[2:0] == 3) begin
            n_mv_valid = 1'b1;
            if (mv_addr == 47) begin
                n_mv_addr = 0;
            end
            else begin
                n_mv_addr = mv_addr + 1;
            end
        end
    end
end

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state    <= IDLE;
        mv_valid <= 1'b0;
        mv_col   <= 2'b00;
        mv_addr  <= 47;
        for (i=0;i<`PIXEL_NUM;i=i+1) begin
            base_frame[i] <= 3'd0;
        end
        frame_count     <= 4'd0;
        pixel_col_count <= 6'd1;
        pixel_row_count <= 6'd0;
        for (j=1;j<=6;j=j+1) begin
            for (k=0;k<4;k=k+1) begin
                SAD[j][k] <= 0;
            end
        end
        best_SAD <= 0;
    end 
    else begin
        state    <= n_state;
        mv_valid <= n_mv_valid;
        mv_col   <= n_mv_col;
        mv_addr  <= n_mv_addr;
        for (i=0;i<`PIXEL_NUM;i=i+1) begin
            base_frame[i] <= n_base_frame[i];
        end
        frame_count     <= n_frame_count;
        pixel_col_count <= n_pixel_col_count;
        pixel_row_count <= n_pixel_row_count;
        for (j=1;j<=6;j=j+1) begin
            for (k=0;k<4;k=k+1) begin
                SAD[j][k] <= n_SAD[j][k];
            end
        end
        best_SAD <= n_best_SAD;
    end   
end
endmodule
