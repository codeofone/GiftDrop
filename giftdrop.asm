; --------------------------------------
; constants
; --------------------------------------
R6510           = $0001
VIC_START       = $d000
RASTER_HI       = $d011
RASTER          = $d012
VIC_CTRL        = $d018
IRQ_STATUS      = $d019
IRQ_ENABLE      = $d01a
VIC_SPRENABLE   = $d015
VIC_SPRMULTI    = $d01c
VIC_SPRMC1      = $d025
VIC_SPRMC2      = $d026
VIC_SPRX        = $d000
VIC_SPRXMSB     = $d010
VIC_SPRDATA     = $bbf8
VIC_SPRCOLOR    = $d027
VIC_COLLIDED    = $d01e
VIC_SCRNRAM     = $b800
VIC_COLRRAM     = $d800
SID_FREQ1_LO    = $d400
SID_FREQ1_HI    = $d401
SID_PULWAV1_LO  = $d402
SID_PULWAV1_HI  = $d403
SID_CTRL1       = $d404
SID_ATKDEC      = $d405
SID_SUSREL      = $d406
SID_VOL         = $d418
CI2PRA          = $dd00
C2DDRA          = $dd02
JIFFY_LO        = $00a2
KEYMATRX        = $00cb
IRQ_VECT        = $0314
JIFFY_LO        = $00a2
JIFFY_MID       = $00a1
JIFFY_HI        = $00a0

K_GETIN         = $ffe4

; zp
ZP_VALUE        = $02
ZP_VALUE_HI     = $03
PTR             = $fb
PTR_HI          = $fc
PTR2            = $fd
PTR2_HI         = $fe
SCRNDATA        = $22
SCRNDATA_HI     = $23
SCRNCOUNT       = $24
SCRNCODE        = $25
ZP_BYTE         = $ff

KBBUFFCOUNT     = $00c6
JOY2_REG        = $dc00
JOY1_REG        = $dc01
JOY_UP          = $01
JOY_DOWN        = $02
JOY_LEFT        = $04
JOY_RIGHT       = $08
JOY_BUTTON      = $10
JOY_NONE        = $80

DIR_NONE        = 0
DIR_LEFT        = 1
DIR_RIGHT       = 2
DIR_FALL        = 4

GS_PAUSE        = 0
GS_PLAY         = 1
GS_FAIL         = 64
GS_OVER         = 128

ANIM_SPEED      = $04
MOVE_SPEED      = $02
ELF_DIR_SPEED   = $48

START_X         = $0100         ; santa starting x location
START_Y         = $dc           ; santa starting y location
SANTA_SPEED     = $0a           ; santa move speed per frame
ELF_SPEED       = $08           ; elf move speed per frame

SANTA_Y         = $dc           ; normal santa y loc
SANTA_FLOOR_Y   = $e4           ; santa y loc on the floor

BOUND_X_MAX     = $010c         ; left bounds for sprites
BOUND_X_MIN     = $16           ; right bounds for sprites

GIFT_RATE       = $78           ; initial gift drop rate
GIFT_FALL_SPEED = $02           ; initial gift speed
GIFT_MAX_RATE   = $30           ; max gift drop rate
GIFT_MAX_SPEED  = $04           ; max gift speed
GIFT_MAX_Y      = $e8
GIFT_MAX_INHAND = $11           ; actually max+1

DIFF_INC_RATE   = 10            ; how often difficulty increases

LOC_CAUGHT_SCOR = $b807         ; 47111 screen RAM
LOC_LOADED_SCOR = $b81c
LOC_LOADED_LO   = $b81e 
LOC_DROPPED_SCOR= $b812

GAME_OVER_DROP  = $25           ; game over if dropped this many

*=$c000



; --------------------------------------
;
; Game start, init
;
; --------------------------------------
        jsr render_game_screen 
        ; init all scores to 0
        lda #0
        sta gifts_dropped
        sta gifts_inhand
        sta gifts_loaded
        sta gifts_loaded+1
        sta gifts_total
        ; reset gift sprites
        ldy #3
@giftloop
        cpy #8
        beq @endgiftpos
        sta gift_active,y       ; reset active flag
        sta sprite_y,y          ; set gift y to 0
        iny
        jmp @giftloop
@endgiftpos
        ; initial sprite positions
        ldx #1
        lda #$00                ; santa
        sta sprite_x_lo
        lda #$01
        sta sprite_x_hi
        lda #$c8                ; elf 1
        sta sprite_x_lo,x
        lda #$00
        sta sprite_x_hi,x
        inx
        lda #$90                ; elf 2
        sta sprite_x_lo,x
        lda #$01
        sta sprite_x_hi,x  
        ; display sprites in inital pos
        jsr update_all_sprites
        ; clear keyboard buffer
        lda #0
        sta KBBUFFCOUNT
        ; gift drop rate
        lda #GIFT_RATE
        sta gift_tmr_reset
        sta gift_tmr
        ; init SID
        lda #15
        sta SID_VOL
        lda #48                 ; Attack/Decay
        sta SID_ATKDEC
        lda #160
        sta SID_SUSREL          ; Sustain/Release
        ; enable the irq handler
        jsr irq_on  
        

; --------------------------------------
;
; Game loop
;
; --------------------------------------
gameloop
        lda JOY2_REG            ; read joystick
        eor #$ff                ; isolate joystick pos
        and #15
        sta joystate
        ; if gifts in hand 
        ; over limit, santa falls
        lda gifts_inhand
        cmp #GIFT_MAX_INHAND
        bcc @continue
        jsr knock_santa_down
@continue
        ; check for game over
        lda gifts_dropped
        cmp #GAME_OVER_DROP
        bcc @endloop
        jmp @endgame
@endloop
        ; continue with game loop
        jmp gameloop
@endgame
        ; turn off irq
        jsr irq_off
        ; turn off sprites
        lda #0
        sta VIC_SPRENABLE
        ; stop any sound that might be playing
        jsr stop_note
        ; display game over text (1437)
        lda #$9d
        sta PTR
        lda #$b9
        sta PTR_HI
        lda #$9d
        sta PTR2
        lda #$d9
        sta PTR2_HI
        ldy #0
@gameover
        lda game_over_str,y
        sta (PTR),y
        lda #1
        sta (PTR2),y
        iny
        cpy #9
        bne @gameover
        ; pause for 4 seconds
        lda #240
        jsr pause
        ; load final score to zp
        lda gifts_loaded
        sta PTR
        lda gifts_loaded+1
        sta PTR_HI
        rts



; --------------------------------------
;
; setup and enable irq handler
;
; --------------------------------------
irq_on
        ; disable interrupts for a sec
        sei
        ; maintain original irq pointer
        lda IRQ_VECT
        sta irq_default
        lda IRQ_VECT+1
        sta irq_default+1
        ; install custom irq handler
        lda #<irq_handler
        sta IRQ_VECT
        lda #>irq_handler
        sta IRQ_VECT+1
        ; trigger raster interrupt at 249
        ; also enable sprite collisions
        lda IRQ_ENABLE
        ora #5
        sta IRQ_ENABLE
        lda #249
        sta RASTER
        lda RASTER_HI
        and #127
        sta RASTER_HI
        ; clear irq flags
        lda #$f
        sta IRQ_STATUS
        lda VIC_COLLIDED
        ; clear interrupt disable
        cli
        rts


; --------------------------------------
; irq_off
; --------------------------------------
irq_off
        sei
        ; remove customer irq handler
        lda irq_default
        sta IRQ_VECT
        lda irq_default+1
        sta IRQ_VECT+1
        ; disable sprite collisions
        ; and raster irq's
        lda #0
        sta IRQ_ENABLE
        cli
        rts
        

; --------------------------------------
; IRQ Handler
;
; --------------------------------------
irq_handler
        ;inc $d020
        lda IRQ_STATUS
        bmi @handleirq          ; skip if not a VIC irq
        jmp @end
@handleirq
        sta irq_flags
        and #1
        bne @raster_int
        lda irq_flags
        and #4
        beq @no_irq        
        jmp @chk_spr_collisions
@no_irq
        jmp @end
@raster_int
        ; clear raster interrupt
        lda #1
        sta IRQ_STATUS 
        ; play current note
        jsr play_note           ; play current sound
        ; skip if santa is down
        lda santa_dir
        cmp #DIR_FALL
        beq @end
        ; handle animation
        dec anim_timer          ; animation timer
        bne @chk_gift_drop_timer; not time to animate
        lda #ANIM_SPEED
        sta anim_timer
        jsr update_santa_dir    ; set santa orientation
        jsr anim_santa_sprite   ; set the correct sprite ptr
        ldy #0
        jsr anim_elf_sprite     ; set correct sprite
        ldy #1
        jsr anim_elf_sprite
@chk_gift_drop_timer
        dec gift_tmr
        bne @elf_dir_chg_timer
        lda gift_tmr_reset
        sta gift_tmr
        jsr elf_drop_gift        
@elf_dir_chg_timer
        dec elf_dir_timer
        bne @chk_move_timer
        lda #ELF_DIR_SPEED
        sta elf_dir_timer
        inc elf_flipflop        ; elves take turns changing dir
        ldy elf_flipflop
        cpy #2
        bcc @upd_elf_dir
        ldy #0
        sty elf_flipflop
@upd_elf_dir
        jsr update_elf_dir      ; update elf 1 dir        
@chk_move_timer
        dec move_timer          ; keep movement rate steady
        bne @end
        lda #MOVE_SPEED         ; reset frame timer
        sta move_timer
        ldx #0
        jsr move_sprite         ; move santa if needed
        ldx #1
        jsr move_sprite
        ldx #2
        jsr move_sprite
        jsr move_gifts
        ; sprite updates
        jsr update_all_sprites
        jmp @end
@endcollision
        ; clear sprite collision irq
        lda #4
        sta IRQ_STATUS
        lda VIC_COLLIDED
@end
        ;dec $d020
        jmp (irq_default)

@chk_spr_collisions
        lda VIC_COLLIDED
        sta irq_flags
        and #1                  ; is collision with santa?
        beq @endcollision
        ldy #7
@loop
        asl irq_flags
        bcs @found_collision        
        dey
        cpy #2
        beq @endcollision       ; no collision w/ gift
        jmp @loop

@found_collision
        lda #<snd_new_catch
        ldx #>snd_new_catch
        jsr play_sound
        jsr deactivate_gift     ; y = gift collided with        
        jsr add_gifts_inhand    ; add 1 to gifts caught
        jsr display_caught      ; display gifts caught
        lda gifts_inhand        ; see if santa caught 
        jmp @endcollision



; --------------------------------------
; update_all_sprites
; --------------------------------------
update_all_sprites
        ldy #7
@loopsprites                
        tya
        pha
        jsr update_sprite       ; render sprites to screen        
        pla
        tay
        cpy #0
        beq @end
        dey
        jmp @loopsprites
@end
        rts




; --------------------------------------
;
; set santa dir per joystick dir
;
; --------------------------------------
update_santa_dir
        lda santa_dir
        cmp #DIR_FALL
        bne @continue
        rts
@continue
        lda joystate
        cmp #JOY_LEFT
        bne @chk_right
        lda #DIR_LEFT
        sta santa_dir
        rts
@chk_right 
        cmp #JOY_RIGHT
        bne @no_dir
        lda #DIR_RIGHT
        sta santa_dir
        rts
@no_dir
        lda #DIR_NONE
        sta santa_dir
        rts



; --------------------------------------
;
; set elf dir randomly
;  
; setup
;  y = elf number (0-1)        
; --------------------------------------
update_elf_dir
        lda elf_dir,y
        beq @change
        lda JIFFY_LO
        and #1
        beq @end
@change
        ; change dir
        lda elf_dir,y
        cmp #DIR_LEFT
        bne @go_left
        lda #DIR_RIGHT
        sta elf_dir,y
        rts
@go_left
        lda #DIR_LEFT
        sta elf_dir,y
@end
        rts



; --------------------------------------
;
; move sprite
;
; setup
;  x = sprite number (0-7)
; --------------------------------------
move_sprite
        lda #SANTA_SPEED
        sta ZP_BYTE
        lda santa_dir
        cpx #0
        beq @chk_none
        lda #ELF_SPEED
        sta ZP_BYTE
        dex
        lda elf_dir,x
        inx
@chk_none
        cmp #DIR_FALL
        bne @continue
        rts
@continue
        cmp #DIR_NONE
        bne @chk_left
        rts
@chk_left
        cmp #DIR_LEFT
        beq @move_left
        ; move right
        clc
        lda sprite_x_lo,x
        adc ZP_BYTE
        sta sprite_x_lo,x
        lda sprite_x_hi,x
        adc #0
        sta sprite_x_hi,x
        jmp @chk_bounds
@move_left
        sec
        lda sprite_x_lo,x
        sbc ZP_BYTE
        sta sprite_x_lo,x
        lda sprite_x_hi,x
        sbc #0
        sta sprite_x_hi,x
@chk_bounds
        ; get x pos
        lda sprite_x_lo,x
        sta ZP_VALUE
        lda sprite_x_hi,x
        sta ZP_VALUE_HI
        lsr ZP_VALUE_HI
        ror ZP_VALUE
        ; left bounds
        lda ZP_VALUE_HI
        bne @chk_max
        lda ZP_VALUE
        cmp #BOUND_X_MIN
        bcs @end
        lda #BOUND_X_MIN
        asl 
        sta sprite_x_lo,x
        cpx #0                  
        beq @end
        ; if elf, change dir
        dex
        jsr flip_elf_dir
        rts        
@chk_max
        lda ZP_VALUE
        cmp #<BOUND_X_MAX
        bcc @end
        ; to far right, load max into x pos
        lda #<BOUND_X_MAX
        sta sprite_x_lo,x
        lda #>BOUND_X_MAX
        sta sprite_x_hi,x
        ; shift left for fixed float
        asl sprite_x_lo,x
        rol sprite_x_hi,x
        cpx #0                  
        beq @santa_unload
        ; if elf, change dir
        dex
        jsr flip_elf_dir
        jmp @end
@santa_unload
        ; if santa, unload gifts in hand
        lda gifts_inhand
        beq @end
        jsr unload_gifts
@end
        rts



; --------------------------------------
; unload_gifts
; --------------------------------------
unload_gifts
        lda #<snd_new_loaded
        ldx #>snd_new_loaded
        jsr play_sound
        ;sei
        ; add gifts in hand to loaded
        clc
        sed
        lda gifts_loaded
        adc gifts_inhand
        sta gifts_loaded
        lda gifts_loaded+1
        adc #0
        sta gifts_loaded+1
        cld
        ; clear gifts in hand
        lda #0
        sta gifts_inhand
        ; update scores
        jsr display_caught
        jsr display_loaded
        ;cli
        rts



; --------------------------------------
; flip_elf_dir
;
; setup
;  x = elf (0-1)
; --------------------------------------
flip_elf_dir
        lda elf_dir,x
        cmp #DIR_LEFT
        bne @flip_left
        lda #DIR_RIGHT
        sta elf_dir,x
        rts
@flip_left
        lda #DIR_LEFT
        sta elf_dir,x
        rts


; --------------------------------------
;
; determine correct sprite data ptr
; for santa. should only be called when
; frame needs updating.
;
; --------------------------------------
anim_santa_sprite
        lda santa_dir
        cmp #DIR_LEFT
        beq @santa_left
        cmp #DIR_RIGHT
        beq @santa_right
        cmp #DIR_FALL
        bne @santa_standing
        rts
@santa_standing
        ; santa is standing still
        lda #0
        sta santa_frame
        jmp @set_data_ptr
@santa_left
        lda santa_frame
        cmp #2
        beq @first_frame_left        
        lda #2
        sta santa_frame
        jmp @set_data_ptr
@first_frame_left
        lda #1
        sta santa_frame
        jmp @set_data_ptr
@santa_right
        lda santa_frame
        cmp #4
        beq @first_frame_right
        lda #4
        sta santa_frame
        jmp @set_data_ptr
@first_frame_right
        lda #3
        sta santa_frame
@set_data_ptr
        ; update sprite data ptr
        ldy santa_frame
        lda santa_frames,y
        sta VIC_SPRDATA
        rts


; --------------------------------------
; animate elfs
;
;  y = elf number (0-1)
; --------------------------------------
anim_elf_sprite
        lda elf_dir,y
        cmp #DIR_LEFT
        beq @elf_left
        cmp #DIR_RIGHT
        beq @elf_right
        ; elf is standing still
        lda #0
        sta elf_frame,y
        jmp @set_data_ptr
@elf_left
        lda elf_frame,y
        cmp #2
        beq @first_frame_left 
        lda #2
        sta elf_frame,y
        jmp @set_data_ptr
@first_frame_left
        lda #1
        sta elf_frame,y
        jmp @set_data_ptr
@elf_right
        lda elf_frame,y
        cmp #4
        beq @first_frame_right
        lda #4
        sta elf_frame,y
        jmp @set_data_ptr
@first_frame_right
        lda #3
        sta elf_frame,y
@set_data_ptr
        ; update sprite data ptr
        ldx elf_frame,y
        lda elf_frames,x
        iny
        sta VIC_SPRDATA,y
        rts



; --------------------------------------
; update sprite registers
;
; setup
;  y = sprite number (0-7)
; --------------------------------------
update_sprite
        ; update sprite x loc
        lda sprite_x_lo,y
        sta ZP_VALUE
        lda sprite_x_hi,y
        sta ZP_VALUE_HI

        lsr ZP_VALUE_HI
        ror ZP_VALUE        

        ; calc msb bit
        lda #1
        sta ZP_BYTE
        tya
        tax
@loop
        beq @continue
        asl ZP_BYTE
        dex
        jmp @loop
@continue
        lda ZP_VALUE_HI
        beq @turnoffmsb
        ; turn on msb
        lda ZP_BYTE
        ora VIC_SPRXMSB
        sta VIC_SPRXMSB
        jmp @setxy
@turnoffmsb
        lda ZP_BYTE
        eor #$ff
        and VIC_SPRXMSB         ; x msb bit
        sta VIC_SPRXMSB
@setxy
        ; set sprite x,y        
        lda sprite_y,y          ; get y loc
        pha                     ; put on stack
        tya                     ; mul to get index
        asl                     ; into x/y registers
        tay
        lda ZP_VALUE            ; sprite x lo byte
        sta VIC_SPRX,y          ; x lo byte
        iny                     ; y reg follows x reg
        pla                     ; pop y loc off stack
        sta VIC_SPRX,y          ; y loc

        rts


; --------------------------------------
; drop gift
;
; setup
;  a=lo byte of sprite x
;  x=hi byte of sprite x
;  y=sprite y
; --------------------------------------
drop_gift
        sta ZP_VALUE
        stx ZP_VALUE_HI
        sty ZP_BYTE
        ; find avail gift sprite
        ldy #0
@loop
        lda gift_active,y
        beq @activate
        iny        
        cpy #5
        bne @loop
        rts
@activate
        ; play sound
        lda #<snd_new_gift
        ldx #>snd_new_gift
        jsr play_sound
        ; allocate gift
        lda #1
        sta gift_active,y       ; mark as used
        iny                     ; gifts start
        iny                     ; at sprite 3
        iny
        lda ZP_VALUE
        cmp #$30
        bcs @setgiftx
        lda #$30
@setgiftx
        sta sprite_x_lo,y
        lda ZP_VALUE_HI
        sta sprite_x_hi,y
        lda ZP_BYTE
        sta sprite_y,y
        lda #254                ; gift sprite data
        sta VIC_SPRDATA,y
        ; inc total gift count
        inc gifts_total
        ; chk time for diff increased
        lda gifts_total
        cmp #DIFF_INC_RATE
        bcc @end
        jsr increase_diff
@end
        rts



; --------------------------------------
; Increase the difficulty
;
; --------------------------------------
increase_diff
        lda #0
        sta gifts_total
        lda gift_tmr
        cmp GIFT_MAX_RATE
        bcc @end
        sec
        sbc #$0a
        sta gift_tmr_reset
@end
        rts



; --------------------------------------
; move gifts
;
; --------------------------------------
move_gifts
        ldy #3
        ldx #0
@loop
        lda gift_active,x
        beq @next
        lda sprite_y,y
        cmp #GIFT_MAX_Y
        bcc @continue
        tya
        pha
        jsr deactivate_gift
        lda #<snd_new_drop
        ldx #>snd_new_drop
        jsr play_sound
        jsr add_gifts_dropped
        jsr display_gifts_dropped
        pla
        tay
        jmp @next
@continue
        clc
        lda sprite_y,y
        adc gift_speed
        sta sprite_y,y 
@next       
        iny
        inx
        cpy #8
        bcc @loop
        rts        




; --------------------------------------
; deactivate gift
;
; setup:
;  y = gift sprite (3-7) to deactivate
; --------------------------------------
deactivate_gift
        lda #0
        sta sprite_y,y  ; move gift sprite off screen
        dey
        dey
        dey
        sta gift_active,y
        iny
        iny
        iny
        jsr update_sprite
        rts


; --------------------------------------
; pick elf to drop gift
;
; --------------------------------------
elf_drop_gift  
        ldy elf_flipflop
        lda elf_dir,y
        beq @end         ; don't drop if not moving
        ;lda #DIR_NONE
        ;sta elf_dir,y
        ;lda #3           ; short dir chang timer
        ;sta elf_dir_timer
        iny
        lda sprite_y,y
        clc
        adc #21
        sta ZP_BYTE
        lda sprite_x_hi,y
        tax
        lda sprite_x_lo,y
        clc
        adc #12
        ldy ZP_BYTE
        jsr drop_gift        
@end
        rts


; --------------------------------------
; increment gifts caught
;
;
; --------------------------------------
add_gifts_inhand
        sed
        lda gifts_inhand
        clc
        adc #1
        sta gifts_inhand
        cld
        rts



; --------------------------------------
; increment gifts dropped
;
;
; --------------------------------------
add_gifts_dropped
        sed
        lda gifts_dropped
        clc
        adc #1
        sta gifts_dropped
        cld
        rts



; --------------------------------------
; Knock Santa down, too many gifts.
; --------------------------------------
knock_santa_down
        ; add gifts in hand to dropped total
        sed
        lda gifts_dropped
        clc
        adc gifts_inhand
        sta gifts_dropped         
        ; remove all gifts in hand
        lda #0
        sta gifts_inhand
        cld
        ; update scores
        jsr display_caught
        jsr display_gifts_dropped
        ; change santa sprite to fallen
        lda #$ff
        sta VIC_SPRDATA
        ; position santa on floor        
        lda #SANTA_FLOOR_Y
        sta VIC_SPRX+1
        ; set dir to fallen
        lda #DIR_FALL
        sta santa_dir
        ; play song
        lda #<snd_santa_fall
        ldx #>snd_santa_fall
        jsr play_sound
        ; wait until no song playing
@loopsong
        lda snd_active
        bne @loopsong
        ; change santa to standing
        lda #DIR_NONE
        sta santa_dir
        ; move santa back up to original Y
        lda #SANTA_Y
        sta VIC_SPRX+1
        rts
        


; --------------------------------------
; display_caught
;
; --------------------------------------
display_caught
        lda gifts_inhand
        cmp #8
        bcc @brd_black
        ldx #2
        stx $d020
        jmp @continue
@brd_black
        ldx #0
        stx $d020
@continue
        ldx #<LOC_CAUGHT_SCOR
        ldy #>LOC_CAUGHT_SCOR
        jsr display_number        
        rts



; --------------------------------------
; display_gifts_dropped
;
; --------------------------------------
display_gifts_dropped
        lda gifts_dropped
        ldx #<LOC_DROPPED_SCOR
        ldy #>LOC_DROPPED_SCOR
        jsr display_number
        rts



; --------------------------------------
; display_loaded
;
; --------------------------------------
display_loaded
        lda gifts_loaded
        ldx #<LOC_LOADED_LO
        ldy #>LOC_LOADED_LO
        jsr display_number
        lda gifts_loaded+1
        ldx #<LOC_LOADED_SCOR
        ldy #>LOC_LOADED_SCOR
        jsr display_number
        rts


; --------------------------------------
; display number
;
; setup
;  a = bcd decimal to display (2 digits)
;  x = lo byte of screen location
;  y = hi byte of screen location
;  
; --------------------------------------
display_number
        ; will need to get number back
        pha  
        ; isolate lo nyble
        and #$f
        clc
        adc #48
        ; right digit
        stx PTR
        sty PTR_HI
        ldy #1
        sta (PTR),y
        ; calc left digit char
        pla
        lsr
        lsr
        lsr
        lsr
        clc
        adc #48
        ; left digit
        dey
        sta (PTR),y
        rts




; --------------------------------------
; play a sound
;
; a = lo byte of sound data
; x = hi byte of sound data
; --------------------------------------
play_sound
        sta snd_ptr
        stx snd_ptr+1
        lda #0
        sta snd_note        
        lda #1
        sta snd_active
        sta snd_tmr
        rts



; --------------------------------------
; play next sound note
;
; --------------------------------------
play_note
        ; if no sound active, exit
        lda snd_active        
        beq @end
        ; chk current note timer
        lda snd_tmr                        
        ; if finished end the note
        beq @next_note
        ; not finished
        dec snd_tmr
        jmp @end
@next_note
        ; close the gate
        jsr stop_note
        ; get index into current sound
        ldy snd_note
        ; load freq pointer
        lda snd_ptr        
        sta PTR        
        lda snd_ptr+1
        sta PTR_HI        
        ; load freq
        lda (PTR),y
        beq @end_sound
        sta SID_FREQ1_LO
        iny
        lda (PTR),y
        sta SID_FREQ1_HI
        ; load note length
        iny
        lda (PTR),y
        sta snd_tmr
        ; update note nbr
        iny
        sty snd_note
        ; open the gate
        lda #17
        sta SID_CTRL1 
        ; exit
        jmp @end
@end_sound
        jsr stop_note
        lda #0
        sta snd_active
        sta snd_tmr
@end
        rts


; --------------------------------------
; close the SID gate to end the current 
; note
;
; --------------------------------------
stop_note
        ; close the gate
        lda #16
        sta SID_CTRL1
        rts


; --------------------------------------
; pause for seconds
;
; a = number of jiffies
;
; --------------------------------------
pause
        ; add current time
        clc
        adc JIFFY_LO
        sta ZP_VALUE
@loop
        lda JIFFY_LO
        cmp ZP_VALUE
        bne @loop
        rts


; --------------------------------------
; render game screen
;
; --------------------------------------
render_game_screen
        lda #<VIC_SCRNRAM
        sta PTR
        lda #>VIC_SCRNRAM
        sta PTR_HI
        lda #<game_screen
        sta SCRNDATA
        lda #>game_screen 
        sta SCRNDATA_HI        
@loop
        ldy #0
        lda (SCRNDATA),y      ; screen code
        sta SCRNCODE
        iny
        lda (SCRNDATA),y      ; count
        beq @load_color         ; exit when cnt is 0
        sta SCRNCOUNT
        tax
        lda SCRNCODE
        ldy #0
@rpt       
        sta (PTR),y             ; output scrn code y times
        iny
        dex
        bne @rpt
        ; move screen ptr
        clc
        lda PTR
        adc SCRNCOUNT
        sta PTR
        lda PTR_HI
        adc #0
        sta PTR_HI
        ; move game data ptr
        clc
        lda SCRNDATA
        adc #2
        sta SCRNDATA
        lda SCRNDATA_HI
        adc #0
        sta SCRNDATA_HI

        jmp @loop

@load_color
        lda #<VIC_COLRRAM
        sta PTR
        lda #>VIC_COLRRAM
        sta PTR_HI
        lda #<game_color
        sta SCRNDATA
        lda #>game_color 
        sta SCRNDATA_HI        
@loopc
        ldy #0
        lda (SCRNDATA),y      ; color
        sta SCRNCODE
        iny
        lda (SCRNDATA),y      ; count
        beq @end              ; exit when cnt is 0
        sta SCRNCOUNT
        tax
        lda SCRNCODE
        ldy #0
@rptc   
        sta (PTR),y             ; output color y times
        iny
        dex
        bne @rptc
        ; move screen ptr
        clc
        lda PTR
        adc SCRNCOUNT
        sta PTR
        lda PTR_HI
        adc #0
        sta PTR_HI
        ; move game data ptr
        clc
        lda SCRNDATA
        adc #2
        sta SCRNDATA
        lda SCRNDATA_HI
        adc #0
        sta SCRNDATA_HI

        jmp @loopc
@end
        rts

        




; game text        
game_over_str   byte $07,$01,$0d,$05,$20,$0f,$16,$05,$12

; timers
anim_timer      byte ANIM_SPEED ; countdown until next animation
move_timer      byte MOVE_SPEED ; countdown until next frame
elf_dir_timer   byte $20        ; countdown until elves change dir

; sound data
snd_active      byte $00        ; 1=sound is playing
snd_ptr         word $0000      ; ptr to sound notes
snd_note        byte $00        ; index into notes list
snd_tmr         byte $00        ; current note countdown 
snd_new_gift    byte 1,70,2,1,60,2,1,50,2,1,40,2,00,00,00
snd_new_catch   byte 1,40,2,1,80,2,00,00,00
snd_new_drop    byte 15,16,10,00,00,00
snd_new_loaded  byte 1,32,2,1,42,2,1,52,2,1,62,2,1,72,2,00,00,00
snd_santa_fall  byte 30,25,30, 49,28,15, 30,25,15, 31,21,50
                byte 30,25,30, 49,28,15, 30,25,15, 31,21,50,00,00,00

; game data
game_state      byte GS_PLAY
gift_speed      byte GIFT_FALL_SPEED

; sprite frames
santa_frames    byte 244,247,248,245,246
elf_frames      byte 249,252,253,250,251

; sprite locations
sprite_x_lo     byte $00,$c8,$90,$00,$00,$00,$00,$00
sprite_x_hi     byte $01,$00,$01,$00,$00,$00,$00,$00
sprite_y        byte $dc,$3c,$3c,$00,$20,$40,$60,$80

; santa current dir and frame
santa_dir       byte $00        ; 0=standing 1=left 2=right
santa_frame     byte $00        ; index into santa sprite frames

; elf current dir and frame
elf_dir         byte $00,$00
elf_frame       byte $00,$00
elf_flipflop    byte $00

joystate        byte $00        ; joystick state

; default irq address
irq_default     word $0000
irq_flags       byte $00

gift_active     byte $00,$00,$00,$00,$00
gift_tmr        byte GIFT_RATE  ; countdown until next gift
gift_tmr_reset  byte GIFT_RATE

gifts_dropped   byte $00
gifts_loaded    word $0000
gifts_inhand    byte $00
gifts_total     byte $00        ; total # of gifts dropped
                                ; since difficulty increase



game_screen     BYTE    $03,$01,$01,$01,$15,$01,$07,$01,$08,$01,$14,$01,$20,$01,$30,$02,$20,$01,$04,$01,$12,$01,$0F,$01,$10,$02,$05,$01,$04,$01,$20,$01,$30,$02,$20,$01,$0C,$01,$0F,$01,$01,$01,$04,$01,$05,$01,$04,$01,$20,$01,$30,$04,$20,$01,$F4,$01,$A0,$06,$20,$21,$F4,$01,$A0,$06,$20,$21,$F4,$01,$A0,$06,$64,$21,$F4,$01,$A0,$06,$D6,$21,$F4,$01,$A0,$06,$63,$21,$F4,$01,$A0,$06,$20,$21,$F4,$01,$A0,$06,$20,$21,$F4,$01,$A0,$06,$20,$21,$F4,$01,$A0,$06,$20,$10,$CE,$01,$20,$10,$F4,$01,$A0,$06,$20,$21,$F4,$01,$A0,$06,$20,$21,$F4,$01,$A0,$06,$20,$21,$F4,$01,$A0,$06,$20,$05,$2A,$01,$20,$1B,$F4,$01,$A0,$06,$20,$04,$E9,$01,$A0,$01,$DF,$01,$20,$1A,$F4,$01,$A0,$06,$20,$03,$E9,$01,$A0,$01,$DC,$01,$A0,$01,$DF,$01,$20,$19,$F4,$01,$A0,$06,$20,$03,$E9,$01,$A0,$01,$AE,$01,$A0,$01,$DF,$01,$20,$07,$64,$05,$20,$0D,$F4,$01,$A0,$06,$20,$03,$E9,$01,$DC,$01,$A0,$02,$DF,$01,$20,$06,$6A,$01,$A0,$02,$DD,$01,$A0,$02,$65,$01,$20,$0C,$F4,$01,$A0,$06,$20,$02,$E9,$01,$A0,$03,$AE,$01,$DC,$01,$DF,$01,$20,$05,$6A,$01,$A0,$02,$DD,$01,$A0,$02,$65,$01,$20,$0C,$F4,$01,$A0,$06,$20,$02,$E9,$01,$A0,$01,$AE,$01,$A0,$03,$DF,$01,$20,$05,$6A,$01,$C3,$01,$C0,$01,$DB,$01,$C0,$01,$C3,$01,$65,$01,$20,$06,$4F,$01,$77,$01,$50,$01,$20,$03,$78,$07,$20,$02,$E9,$01,$A0,$03,$DC,$01,$A0,$01,$DF,$01,$20,$05,$6A,$01,$A0,$02,$DD,$01,$A0,$02,$65,$01,$20,$06,$74,$01,$20,$01,$67,$01,$20,$03,$64,$03,$20,$02,$64,$01,$20,$02,$E9,$01,$A0,$01,$DC,$01,$A0,$01,$AE,$01,$A0,$01,$AE,$01,$A0,$01,$DF,$01,$20,$04,$6A,$01,$A0,$02,$DD,$01,$A0,$02,$65,$01,$20,$06,$74,$01,$6C,$01,$67,$01,$20,$03,$A0,$03,$20,$01,$E9,$01,$A0,$01,$20,$02,$E9,$01,$AE,$01,$A0,$04,$DC,$01,$A0,$01,$DF,$01,$20,$05,$63,$05,$20,$07,$74,$01,$20,$01,$6A,$01,$20,$03,$5F,$01,$A0,$04,$69,$01,$20,$01,$6F,$05,$A0,$01,$6F,$15,$4C,$01,$6F,$01,$7A,$01,$6F,$03,$4A,$01,$71,$01,$40,$02,$71,$01,$4B,$01,$20,$01,$CE,$27,$20,$01,$00,$00
game_color      BYTE    $07,$06,$01,$04,$02,$07,$01,$04,$0D,$06,$01,$05,$00,$01,$06,$07,$00,$0A,$01,$11,$00,$06,$06,$07,$00,$12,$01,$02,$00,$0D,$06,$07,$01,$21,$06,$07,$0F,$21,$06,$07,$00,$21,$06,$07,$00,$21,$06,$07,$00,$21,$06,$07,$00,$13,$02,$02,$00,$03,$05,$04,$00,$05,$06,$07,$00,$10,$0C,$01,$02,$02,$00,$04,$05,$06,$00,$04,$06,$07,$00,$12,$02,$01,$00,$01,$02,$01,$00,$02,$05,$05,$00,$05,$06,$07,$00,$21,$06,$07,$00,$11,$02,$02,$00,$0E,$06,$07,$00,$05,$07,$01,$00,$1B,$06,$07,$00,$04,$05,$03,$00,$1A,$06,$07,$00,$03,$05,$05,$00,$0D,$0E,$05,$00,$07,$06,$07,$00,$03,$05,$05,$00,$0D,$0E,$05,$00,$07,$06,$07,$00,$03,$05,$05,$00,$05,$0E,$01,$00,$01,$06,$05,$00,$03,$0E,$03,$00,$07,$06,$07,$00,$02,$05,$07,$00,$04,$0E,$01,$00,$01,$06,$05,$00,$01,$0E,$06,$00,$05,$0F,$01,$06,$07,$00,$02,$05,$07,$00,$02,$0E,$01,$00,$03,$06,$05,$00,$01,$0E,$04,$0F,$02,$00,$06,$01,$07,$00,$02,$05,$07,$00,$01,$0E,$04,$00,$01,$06,$05,$00,$05,$0E,$02,$00,$04,$02,$01,$00,$01,$07,$03,$00,$02,$07,$02,$05,$0A,$00,$01,$0E,$01,$00,$01,$0E,$01,$00,$01,$06,$05,$00,$01,$0E,$03,$00,$01,$0F,$02,$00,$03,$02,$02,$00,$01,$02,$03,$00,$01,$02,$03,$00,$01,$05,$09,$00,$05,$01,$05,$0E,$01,$00,$09,$02,$02,$00,$01,$02,$07,$00,$05,$09,$01,$00,$1B,$07,$07,$0B,$27,$01,$01,$00,$00
