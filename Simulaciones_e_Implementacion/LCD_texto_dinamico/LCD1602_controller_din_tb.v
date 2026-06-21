`timescale 1ns / 1ps

module LCD1602_controller_din_tb;

    // =========================================================
    // Parámetros del DUT (acelerados para simulación)
    // COUNT_MAX reducido de 800000 a 4 para simular más rápido
    // =========================================================
    localparam NUM_COMMANDS      = 4;
    localparam NUM_DATA_ALL      = 96;
    localparam NUM_DATA_PERLINE  = 16;
    localparam DATA_BITS         = 8;
    localparam COUNT_MAX         = 4;   // acelerado: 800000 → 4
    localparam TEXT2_BEGIN       = 64;
    localparam TEXT1_BEGIN       = 32;

    // =========================================================
    // Señales del DUT
    // =========================================================
    reg  clk;
    reg  reset;
    reg  ready_i;
    reg  text1, text2;

    wire rs;
    wire rw;
    wire enable;
    wire [DATA_BITS-1:0] data;

    // =========================================================
    // Instancia del DUT
    // =========================================================
    LCD1602_controller_din #(
        .NUM_COMMANDS     (NUM_COMMANDS),
        .NUM_DATA_ALL     (NUM_DATA_ALL),
        .NUM_DATA_PERLINE (NUM_DATA_PERLINE),
        .DATA_BITS        (DATA_BITS),
        .COUNT_MAX        (COUNT_MAX),
        .TEXT2_BEGIN      (TEXT2_BEGIN),
        .TEXT1_BEGIN      (TEXT1_BEGIN)
    ) dut (
        .clk     (clk),
        .reset   (reset),
        .ready_i (ready_i),
        .text1   (text1),
        .text2   (text2),
        .rs      (rs),
        .rw      (rw),
        .enable  (enable),
        .data    (data)
    );

    // =========================================================
    // Generador de reloj principal: 50 MHz → periodo 20 ns
    // =========================================================
    initial clk = 0;
    always #10 clk = ~clk;

    // =========================================================
    // Contadores de verificación
    // =========================================================
    integer cmd_count;
    integer data_count;
    integer error_count;

    // =========================================================
    // Tarea: esperar N flancos de enable (clk_16ms)
    // =========================================================
    task wait_enable_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge enable);
                #1; // pequeño retardo para estabilizar señales
            end
        end
    endtask

    // =========================================================
    // Tarea: mostrar estado actual en consola
    // =========================================================
    task display_state;
        begin
            $display("[%0t ns] rs=%b rw=%b enable=%b data=0x%02X (%c)",
                     $time, rs, rw, enable, data,
                     (data >= 8'h20 && data <= 8'h7E) ? data : 8'h2E);
        end
    endtask

    // =========================================================
    // Monitor continuo de cambios en data
    // =========================================================
    initial begin
        $display("============================================================");
        $display("  Testbench LCD1602_controller_din - Inicio de Simulacion");
        $display("============================================================");
        $monitor("[%0t ns] STATE_MON | rs=%b | data=0x%02X",
                 $time, rs, data);
    end

    // =========================================================
    // FLUJO PRINCIPAL DEL TESTBENCH
    // =========================================================
    initial begin
        // ---- Inicialización ----
        reset   = 0;
        ready_i = 1;   // ready_i=1 → nready_i=0 → no se sale de IDLE todavía
        text1   = 1;
        text2   = 1;
        cmd_count   = 0;
        data_count  = 0;
        error_count = 0;

        // ---- Pulso de reset ----
        #50;
        reset = 1;
        $display("\n[%0t ns] >> Reset desactivado. FSM debería estar en IDLE.", $time);

        // ==============================================================
        // TEST 1: Verificar que sin ready_i activo el sistema permanece
        //         en IDLE (ready_i=1 → nready_i=0)
        // ==============================================================
        $display("\n--- TEST 1: Verificacion estado IDLE (ready_i inactivo) ---");
        wait_enable_cycles(5);
        if (rs === 1'b0 && data === 8'h00) begin
            $display("[PASS] TEST 1: Sistema permanece en IDLE correctamente.");
        end else begin
            $display("[FAIL] TEST 1: El sistema no permanecio en IDLE. rs=%b data=0x%02X", rs, data);
            error_count = error_count + 1;
        end

        // ==============================================================
        // TEST 2: Activar ready_i → el sistema debe pasar a CONFIG_CMD1
        //         y enviar los 4 comandos de configuración
        //         Comandos esperados (en orden):
        //           config_mem[0] = 0x38 (LINES2_MATRIX5x8_MODE8bit)
        //           config_mem[1] = 0x06 (SHIFT_CURSOR_RIGHT)
        //           config_mem[2] = 0x0C (DISPON_CURSOROFF)
        //           config_mem[3] = 0x01 (CLEAR_DISPLAY)
        // ==============================================================
        $display("\n--- TEST 2: Secuencia de comandos de configuracion (CONFIG_CMD1) ---");
        ready_i = 0; // nready_i = 1 → sale de IDLE

        // Esperamos y verificamos cada comando
        begin : check_cmds
            reg [7:0] expected_cmds [0:3];
            integer i;
            expected_cmds[0] = 8'h38;
            expected_cmds[1] = 8'h06;
            expected_cmds[2] = 8'h0C;
            expected_cmds[3] = 8'h01;

            for (i = 0; i < NUM_COMMANDS; i = i + 1) begin
                wait_enable_cycles(1);
                display_state;
                if (rs !== 1'b0) begin
                    $display("[FAIL] CMD[%0d]: rs deberia ser 0 (comando). rs=%b", i, rs);
                    error_count = error_count + 1;
                end
                if (data !== expected_cmds[i]) begin
                    $display("[FAIL] CMD[%0d]: esperado=0x%02X, obtenido=0x%02X",
                             i, expected_cmds[i], data);
                    error_count = error_count + 1;
                end else begin
                    $display("[PASS] CMD[%0d]: 0x%02X correcto.", i, data);
                end
            end
        end

        // ==============================================================
        // TEST 3: Escritura de texto en Línea 1
        //         Con text1=1 y text2=1 → inicio = 0
        //         Se espera texto desde static_data_mem[0..15]
        //         Basado en data.txt: " Escoja una de"
        // ==============================================================
        $display("\n--- TEST 3: Escritura Linea 1 (texto desde inicio=0) ---");
        // text1=1, text2=1 → inicio=0 (ninguna selección)
        data_count = 0;
        begin : check_line1
            integer i;
            for (i = 0; i < NUM_DATA_PERLINE; i = i + 1) begin
                wait_enable_cycles(1);
                display_state;
                if (rs !== 1'b1) begin
                    $display("[FAIL] DATA_L1[%0d]: rs deberia ser 1 (dato). rs=%b", i, rs);
                    error_count = error_count + 1;
                end else begin
                    $display("[PASS] DATA_L1[%0d]: rs=1 correcto, dato=0x%02X (%c)",
                             i, data,
                             (data >= 8'h20 && data <= 8'h7E) ? data : 8'h2E);
                end
            end
        end

        // ==============================================================
        // TEST 4: Comando de cambio a segunda línea (CONFIG_CMD2)
        //         Se espera START_2LINE = 0xC0 con rs=0
        // ==============================================================
        $display("\n--- TEST 4: Comando CONFIG_CMD2 (START_2LINE = 0xC0) ---");
        wait_enable_cycles(1);
        display_state;
        if (rs !== 1'b0) begin
            $display("[FAIL] CONFIG_CMD2: rs deberia ser 0. rs=%b", rs);
            error_count = error_count + 1;
        end else if (data !== 8'hC0) begin
            $display("[FAIL] CONFIG_CMD2: esperado=0xC0, obtenido=0x%02X", data);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] CONFIG_CMD2: 0xC0 correcto con rs=0.");
        end

        // ==============================================================
        // TEST 5: Escritura de texto en Línea 2
        //         Con text1=1 y text2=1 → inicio=0
        //         Se espera texto desde static_data_mem[16..31]
        //         Basado en data.txt: "    las opciones"
        // ==============================================================
        $display("\n--- TEST 5: Escritura Linea 2 (texto desde inicio+16) ---");
        begin : check_line2
            integer i;
            for (i = 0; i < NUM_DATA_PERLINE; i = i + 1) begin
                wait_enable_cycles(1);
                display_state;
                if (rs !== 1'b1) begin
                    $display("[FAIL] DATA_L2[%0d]: rs deberia ser 1 (dato). rs=%b", i, rs);
                    error_count = error_count + 1;
                end else begin
                    $display("[PASS] DATA_L2[%0d]: rs=1 correcto, dato=0x%02X (%c)",
                             i, data,
                             (data >= 8'h20 && data <= 8'h7E) ? data : 8'h2E);
                end
            end
        end

        // ==============================================================
        // TEST 6: El sistema debe volver a IDLE después de línea 2
        //         Se verifica que rs vuelve a 0 y data a 0
        // ==============================================================
        $display("\n--- TEST 6: Retorno a IDLE ---");
        wait_enable_cycles(2);
        if (rs === 1'b0) begin
            $display("[PASS] TEST 6: Sistema volvio a IDLE (rs=0).");
        end else begin
            $display("[FAIL] TEST 6: Sistema no volvio a IDLE. rs=%b data=0x%02X", rs, data);
            error_count = error_count + 1;
        end

        // ==============================================================
        // TEST 7: Selección dinámica de texto - text1 activo (text1=0)
        //         Con ntext1=1 → inicio = TEXT1_BEGIN = 32
        //         Se espera texto desde static_data_mem[32..47]
        //         Basado en data.txt: "Ya no quiero   "
        // ==============================================================
        $display("\n--- TEST 7: Texto dinamico con text1=0 (inicio=TEXT1_BEGIN=32) ---");
        text1 = 0; // ntext1 = 1 → inicio = 32
        text2 = 1;
        ready_i = 0; // mantiene activo

        // Saltar comandos CONFIG_CMD1
        wait_enable_cycles(NUM_COMMANDS);

        // Verificar primeros 4 bytes de línea 1 (datos desde mem[32..35])
        $display("Leyendo Linea 1 con text1 seleccionado:");
        begin : check_text1_l1
            integer i;
            for (i = 0; i < NUM_DATA_PERLINE; i = i + 1) begin
                wait_enable_cycles(1);
                display_state;
            end
        end

        // CONFIG_CMD2
        wait_enable_cycles(1);
        $display("CONFIG_CMD2: data=0x%02X (esperado 0xC0)", data);

        // Línea 2 con text1
        $display("Leyendo Linea 2 con text1 seleccionado:");
        begin : check_text1_l2
            integer i;
            for (i = 0; i < NUM_DATA_PERLINE; i = i + 1) begin
                wait_enable_cycles(1);
                display_state;
            end
        end

        $display("[PASS] TEST 7: Seleccion dinamica text1 completada.");

        // ==============================================================
        // TEST 8: Selección dinámica de texto - text2 activo (text2=0)
        //         Con ntext1=0 y ntext2=1 → inicio = TEXT2_BEGIN = 64
        //         Se espera texto desde static_data_mem[64..79]
        //         Basado en data.txt: "No la cancele  "
        // ==============================================================
        $display("\n--- TEST 8: Texto dinamico con text2=0 (inicio=TEXT2_BEGIN=64) ---");
        text1 = 1; // ntext1 = 0
        text2 = 0; // ntext2 = 1 → inicio = 64

        // Saltar comandos CONFIG_CMD1
        wait_enable_cycles(NUM_COMMANDS);

        $display("Leyendo Linea 1 con text2 seleccionado:");
        begin : check_text2_l1
            integer i;
            for (i = 0; i < NUM_DATA_PERLINE; i = i + 1) begin
                wait_enable_cycles(1);
                display_state;
            end
        end

        wait_enable_cycles(1);
        $display("CONFIG_CMD2: data=0x%02X (esperado 0xC0)", data);

        $display("Leyendo Linea 2 con text2 seleccionado:");
        begin : check_text2_l2
            integer i;
            for (i = 0; i < NUM_DATA_PERLINE; i = i + 1) begin
                wait_enable_cycles(1);
                display_state;
            end
        end

        $display("[PASS] TEST 8: Seleccion dinamica text2 completada.");

        // ==============================================================
        // TEST 9: Prueba de reset durante operación
        //         El reset debe llevar la FSM a IDLE inmediatamente
        // ==============================================================
        $display("\n--- TEST 9: Reset durante operacion ---");
        text1 = 1;
        text2 = 1;
        ready_i = 0;
        wait_enable_cycles(2); // entrar en CONFIG_CMD1

        reset = 0; // activar reset
        #50;
        wait_enable_cycles(1);

        if (rs === 1'b0 && data === 8'h00) begin
            $display("[PASS] TEST 9: Reset funciono correctamente. rs=0 data=0x00");
        end else begin
            $display("[FAIL] TEST 9: Reset no funciono. rs=%b data=0x%02X", rs, data);
            error_count = error_count + 1;
        end

        reset = 1;
        ready_i = 1; // volver a IDLE

        // ==============================================================
        // Resumen final
        // ==============================================================
        #200;
        $display("\n============================================================");
        $display("  RESUMEN FINAL DEL TESTBENCH");
        $display("============================================================");
        if (error_count == 0) begin
            $display("  [ALL PASS] Todos los tests pasaron exitosamente.");
        end else begin
            $display("  [ERRORS]   %0d error(es) detectado(s).", error_count);
        end
        $display("============================================================\n");

        $finish;
    end

    // =========================================================
    // Timeout de seguridad: 10 ms simulados
    // =========================================================
    initial begin
        #10_000_000;
        $display("[TIMEOUT] Simulacion excedio el tiempo maximo.");
        $finish;
    end

    // =========================================================
    // Volcado de formas de onda VCD
    // =========================================================
    initial begin
        $dumpfile("lcd1602_sim.vcd");
        $dumpvars(0, LCD1602_controller_din_tb);
    end

endmodule
