module r2wars

import os
import term
import time
import rand
import radare.r2pipe

const (
	arenasize = 512
	maxcycles = 500
)

pub struct Bot {
	name string
	arch string
	bits int
	size int
	battles int
	code string
	data string // # assembled
mut:
	r2 r2pipe.R2Pipe
	cycles int
	regs string
	dead bool
	wins int
	lost int
}

pub struct BattleResult {
	winner &Bot
	loser &Bot
	timeout bool
	cycles int
}

pub struct War {
mut:
	bots []Bot
	// r := r2pipe.new()
}

fn rasm2_flags(file string) ?(string, int) {
	if file.contains('.8051.asm') {
		return '8051', 8
	}
	if file.contains('.8051-8.asm') {
		return '8051', 8
	}
	if file.contains('.x86-16.asm') {
		return 'x86', 16
	}
	if file.contains('.x86-32.asm') {
		return 'x86', 32
	}
	if file.contains('.x86-64.asm') {
		return 'x86', 64
	}
	if file.contains('.arm-64.asm') {
		return 'arm', 64
	}
	if file.contains('.arm-32.asm') {
		return 'arm', 32
	}
	if file.contains('.arm-16.asm') {
		return 'arm', 16
	}
	if file.contains('.mips-32.asm') {
		return 'mips', 32
	}
	if file.contains('.mips-64.asm') {
		return 'mips', 64
	}
	return error('unkwnown arch. $file')
}

fn rasm2(file, flags string) ?string {
	line := 'rasm2 $flags -f $file'
	r := os.exec(line) or {
		return err
	}
	return r.output
}

pub fn new_bot(file string) ?Bot {
	bot_name := file // improve
	bot_code := os.read_file(file) or {
		return error('Cannot open file')
	}
	arch, bits := rasm2_flags(file) or {
		return error(err)
	}
	flags := '-a $arch -b $bits'
	bot_data := rasm2(file, flags) or {
		return error('Cannot open file')
	}
	bot := Bot{
		name: bot_name
		arch: arch
		bits: bits
		wins: 0
		lost: 0
		battles: 0
		code: bot_code
		data: bot_data
		size: bot_data.len / 2
		dead: false
	}
	return bot
}

pub fn new() &War {
	return &War{}
}

fn (mut war War)fight_vs(mut bot0, bot1 Bot) ?BattleResult {
	bot0.r2 = r2pipe.spawn('malloc://$arenasize', 'r2 -q0 -a ${bot0.arch} -b ${bot0.bits}') or {
		panic(err)
	}

	bot1.r2 = r2pipe.spawn('malloc://$arenasize', 'r2 -a ${bot1.arch} -b ${bot1.bits} -q0') or {
		panic(err)
	}
	// eprintln(bot0.r2.cmd('pd 10'))

	res := war.battle(bot0, bot1) or {
		panic(err)
	}
	bot0.r2.free()
	bot1.r2.free()
	return res
}

pub fn (mut war War)fight() ? {
	if war.bots.len < 2 {
		return error('not enough bots')
	}

	items := war.bots.len
	for i in 0 .. items {
		for j in 0 .. items {
			if i != j {
				mut bot := war.bots[i]
				mut but := war.bots[j]
				for _ in 0 .. 3 {
					res := war.fight_vs(bot, but) or {
						panic(err)
					}
					if !res.timeout {
						if res.winner.name == bot.name {
							war.bots[i].wins++
							war.bots[j].lost++
						}
						if res.winner.name == but.name {
							war.bots[i].wins++
							war.bots[j].lost++
						}
					}
				}
			}
		}
	}

	for bot in war.bots {
		println('${bot.wins} / ${bot.lost} - ${bot.name} ')
	}

}

fn randposes(bot0, bot1 &Bot) (int, int) {
	mut pos0 := 0
	mut pos1 := 0
	for true {
		pos0 = rand.intn(arenasize-bot0.size)
		pos1 = rand.intn(arenasize-bot1.size)
		pos0 -= pos0 % 4
		pos1 -= pos1 % 4
		if pos0 < pos1 {
			if pos0 + bot0.size >= pos1 {
				continue
			}
		} else if pos1 < pos0 {
			if pos1 + bot1.size >= pos0 {
				continue
			}
		}
		break
	}
	return pos0, pos1
}

fn setup(mut bot Bot, pc int, sp int) {
	bot.r2.cmd('e asm.bytes=true')
	bot.r2.cmd('e hex.compact=true')
	bot.r2.cmd('e hex.cols=32')
	bot.r2.cmd('e scr.color=2')
	bot.r2.cmd('ar PC=$pc')
	bot.r2.cmd('ar SP=$sp')
	bot.dead = false
	bot.regs = bot.r2.cmd('ar*')
}

pub fn (mut war War)battle(mut bot0, bot1 Bot) ?BattleResult {
	pos0, pos1 := randposes(bot0, bot1)
	print('Positions: $pos0, $pos1')
	mut bot := if rand.intn(2) == 1 { bot0 } else { bot1 }
	bot.r2.cmd('wx ${bot0.data} @ $pos0')
	bot.r2.cmd('wx ${bot1.data} @ $pos1')

	sp := arenasize-4
	setup(mut bot0, pos0, sp)
	setup(mut bot1, pos1, sp)
	term.clear()
	mut cycles := 0
	for true {
		cycles++
		if cycles > maxcycles {
			eprintln('TIMEOUT')
			bot0.dead = true
			bot1.dead = true
			time.sleep(1)
			break
		}
		y := if bot == bot0 { 0 } else { 15 }
		have_cycles := bot.cycles > 0
		mut data := ''
		if have_cycles {
			term.set_cursor_position(0,y)
			println('[$cycles] cc=${bot.cycles} wins=${bot.wins} lost=${bot.lost} ${bot.name}')
			bot.cycles--
			if bot.cycles == 0 {
/*
				for reg in bot.regs.split('\n') {
					bot.r2.cmd(reg)
				}
*/
				bot.r2.cmd('aes')
				bot.r2.cmd('.ar*')
				pc := bot.r2.cmd('ar PC').int()

				pcmap := bot.r2.cmd('om.@r:PC')
// eprintln('PCMAAP(${pcmap.len},$pcmap,${pcmap[0]})')
				if pcmap == '' {
					bot.dead = true
				}
				data = bot.r2.cmd('p8 $arenasize @ 0')
//				bot.regs = bot.r2.cmd('ar*')
			}
		} else {
			// bot.regs = bot.r2.cmd('ar*')
			// bot.r2.cmd(bot.regs)
			cc := bot.r2.cmd('ao@r:PC~cycles[1]').trim_right('\r\n')
			if '$cc' == '' {
				bot.dead = true
			}
			if cc.int() == 0 {
				bot.dead = true
			}
			term.set_cursor_position(0,y)
			println('$bot.cycles')
			term.set_cursor_position(0,y + 2)
			r := bot.r2.cmd('pd 1@r:PC')
			s := bot.r2.cmd('ar=@e:hex.cols=16')
			println('$r\n$s')
			bot.cycles = cc.int()
			// read memory
		}
		term.set_cursor_position(0,32)
		println(bot.r2.cmd('pxa $arenasize @ 0'))

		if bot.dead {
			mut r := bot.r2.cmd('pd 1@r:PC')
			eprintln('IS DEAAAD ${bot.name}\n$r')
			mut winner := if bot == bot0 { bot1 } else { bot0 }
			r = winner.r2.cmd('pd 1@r:PC')
			eprintln('WINNER IS ${winner.name} ${winner.wins}/${winner.lost}\n$r')
			time.sleep(1)
			break
		}
		bot = if bot == bot0 { bot1 } else { bot0 }
		if data != '' {
			bot.r2.cmd('wx $data @ 0')
		}
	}
	return BattleResult {
		winner: if bot0.dead { bot1 } else { bot0 }
		loser: if bot0.dead { bot0 } else { bot1 }
		timeout: bot0.dead && bot1.dead
		cycles: cycles
	}
	// return error('everything exploded')
}

pub fn (mut war War)load_bots(dir string) ? {
	files := os.ls(dir) or {
		return error(err)
	}
	for file in files {
		eprintln('- $file')
		bot := new_bot('$dir/$file') or {
			return error(err)
		}
		war.bots << bot
	}
}

pub fn (war &War)free() {
}
