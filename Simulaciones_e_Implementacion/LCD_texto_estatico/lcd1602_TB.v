`timescale 1ns / 1ps


module LCD1602_controller_TB();

    // ---------------------------------------------------------------
    // Parametros (espejo de los del DUT). COUNT_MAX se reduce a 50
    // para que la simulacion sea rapida: el divisor de clk_16ms ya
    // no tarda 800000 ciclos, sino solo 50.
    // ---------------------------------------------------------------
    localparam NUM_COMMANDS     = 4;
    localparam NUM_DATA_ALL     = 32;
    localparam NUM_DATA_PERLINE = 16;
    localparam DATA_BITS        = 8;
    localparam COUNT_MAX        = 50;

    // ---------------------------------------------------------------
    // Senales de conexion al DUT
    // ---------------------------------------------------------------
    reg clk;
    reg rst;        // Activo en BAJO: el DUT comprueba "if (reset == 0)"
    reg ready_i;

    wire                   rs;
    wire                   rw;
    wire                   enable;
    wire [DATA_BITS-1:0]   data;

    // ---------------------------------------------------------------
    // Memoria de referencia para el autocheck (mismo archivo que usa
    // el DUT). Se compara, en orden, cada caracter que el DUT escribe
    // contra esta copia independiente.
    // ---------------------------------------------------------------
    reg [DATA_BITS-1:0] expected_mem [0:NUM_DATA_ALL-1];

    integer checks   = 0;   // caracteres comparados
    integer errors   = 0;   // discrepancias encontradas
    integer ch_idx   = 0;   // indice del proximo caracter esperado
    integer cmd_idx  = 0;   // comandos de control detectados (rs=0)
    reg     cycle_done = 1'b0;

    // ---------------------------------------------------------------
    // DUT
    // ---------------------------------------------------------------
    LCD1602_controller #(NUM_COMMANDS, NUM_DATA_ALL, NUM_DATA_PERLINE,
                          DATA_BITS, COUNT_MAX) uut (
        .clk     (clk),
        .reset   (rst),
        .ready_i (ready_i),
        .rs      (rs),
        .rw      (rw),
        .enable  (enable),
        .data    (data)
    );

    // ---------------------------------------------------------------
    // Generacion de reloj: 20 ns de periodo (50 MHz)
    // ---------------------------------------------------------------
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // ---------------------------------------------------------------
    // Estimulos de reset y ready_i
    //   - Reset activo en bajo durante 10 ns.
    //   - ready_i se mantiene en 0 un rato tras liberar el reset para
    //     verificar que la FSM se queda correctamente en IDLE, y
    //     luego se activa para disparar la secuencia de escritura.
    // ---------------------------------------------------------------
    initial begin
        rst     = 1'b1;
        ready_i = 1'b0;
        #10  rst = 1'b0;     // pulso de reset
        #10  rst = 1'b1;     // se libera el reset (t = 20 ns)
        #1980 ready_i = 1'b1; // a los 2000 ns, deja que arranque la FSM
    end

    // ---------------------------------------------------------------
    // Carga del archivo de referencia (mismo contenido que usa el DUT)
    // ---------------------------------------------------------------
    initial begin
        $readmemh("data.txt", expected_mem);
    end

    // ---------------------------------------------------------------
    // Volcado de formas de onda
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("LCD1602_controller_TB.vcd");
        $dumpvars(0, LCD1602_controller_TB);
    end

    // ---------------------------------------------------------------
    // Tarea para imprimir el estado de la FSM en cada flanco de
    // clk_16ms (se referencia con jerarquia uut.* porque son senales
    // internas del DUT, utiles solo para verificacion/depuracion)
    // ---------------------------------------------------------------
    task print_status;
        begin
            case (uut.fsm_state)
                uut.IDLE:
                    $display("t=%0t ns | IDLE           | ready_i=%b rs=%b rw=%b data=0x%02h",
                              $time, ready_i, rs, rw, data);
                uut.CONFIG_CMD1:
                    $display("t=%0t ns | CONFIG_CMD1    | cmd_cnt=%0d        rs=%b rw=%b data=0x%02h",
                              $time, uut.command_counter, rs, rw, data);
                uut.WR_STATIC_TEXT_1L:
                    $display("t=%0t ns | WR_STATIC_1L   | data_cnt=%0d       rs=%b rw=%b data=0x%02h ('%c')",
                              $time, uut.data_counter, rs, rw, data, data);
                uut.CONFIG_CMD2:
                    $display("t=%0t ns | CONFIG_CMD2    |                    rs=%b rw=%b data=0x%02h",
                              $time, rs, rw, data);
                uut.WR_STATIC_TEXT_2L:
                    $display("t=%0t ns | WR_STATIC_2L   | data_cnt=%0d       rs=%b rw=%b data=0x%02h ('%c')",
                              $time, uut.data_counter, rs, rw, data, data);
                default:
                    $display("t=%0t ns | ESTADO DESCONOCIDO (%0d)", $time, uut.fsm_state);
            endcase
        end
    endtask

    task print_summary;
        begin
            $display("\n============================================================");
            $display(" RESUMEN DE LA SIMULACION - LCD1602_controller_TB");
            $display("============================================================");
            $display(" Caracteres verificados : %0d / %0d", checks, NUM_DATA_ALL);
            $display(" Comandos de control     : %0d (esperado: %0d)", cmd_idx, NUM_COMMANDS + 1);
            $display(" Errores                : %0d", errors);
            if ((errors == 0) && (checks == NUM_DATA_ALL) && (cmd_idx == NUM_COMMANDS + 1))
                $display(" RESULTADO: PASS - secuencia de escritura correcta.");
            else
                $display(" RESULTADO: FAIL - revisar discrepancias listadas arriba.");
            $display("============================================================\n");
        end
    endtask

    // ---------------------------------------------------------------
    // Monitor + autocheck: en cada flanco de subida de clk_16ms,
    // se espera 1 ns a que las asignaciones no bloqueantes del DUT
    // se asienten y luego se evalua/compara la salida.
    //   - rs=1  -> se interpreta como escritura de un caracter; se
    //              compara contra expected_mem[ch_idx] en orden.
    //   - rs=0 y el DUT no esta en IDLE -> se cuenta como comando de
    //              control real (los 4 de configuracion + START_2LINE).
    //     (Los rs=0/data=0 que ocurren mientras se permanece en IDLE
    //      no son comandos reales hacia el LCD, por eso se excluyen).
    // ---------------------------------------------------------------
    always @(posedge uut.clk_16ms) begin
        #1;
        print_status;
        if (rst) begin
            if (rs == 1'b1) begin
                if (ch_idx < NUM_DATA_ALL) begin
                    checks = checks + 1;
                    if (data !== expected_mem[ch_idx]) begin
                        errors = errors + 1;
                        $display("  >>> MISMATCH caracter #%0d: esperado 0x%02h, obtenido 0x%02h",
                                  ch_idx, expected_mem[ch_idx], data);
                    end
                    ch_idx = ch_idx + 1;
                end
            end else if (uut.fsm_state != uut.IDLE) begin
                cmd_idx = cmd_idx + 1;
            end
        end
    end

    // ---------------------------------------------------------------
    // Invariante: rw nunca deberia activarse (el controlador siempre
    // escribe, nunca lee del LCD)
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rw !== 1'b0)
            $display("t=%0t ns | >>> ERROR: rw deberia ser siempre 0 (solo escritura)", $time);
    end

    // ---------------------------------------------------------------
    // Fin automatico: cuando la FSM vuelve a IDLE habiendo escrito ya
    // los 32 caracteres esperados, se considera completado un ciclo
    // completo y se termina la simulacion con el resumen.
    // ---------------------------------------------------------------
    always @(uut.fsm_state) begin
        if ((uut.fsm_state == uut.IDLE) && (ch_idx == NUM_DATA_ALL) && !cycle_done) begin
            cycle_done = 1'b1;
            #10;
            print_summary;
            $finish;
        end
    end

    // ---------------------------------------------------------------
    // Salvaguarda por si el ciclo no llega a completarse
    // ---------------------------------------------------------------
    initial begin
        $display("================ LCD1602_controller_TB ================");
        $display("NUM_COMMANDS=%0d NUM_DATA_ALL=%0d NUM_DATA_PERLINE=%0d DATA_BITS=%0d COUNT_MAX=%0d",
                   NUM_COMMANDS, NUM_DATA_ALL, NUM_DATA_PERLINE, DATA_BITS, COUNT_MAX);
        $display("=========================================================\n");
        #150000;
        if (!cycle_done) begin
            $display("\n*** TIMEOUT: el ciclo de escritura no termino dentro de la ventana de simulacion ***");
            print_summary;
        end
        $finish;
    end

endmodule
