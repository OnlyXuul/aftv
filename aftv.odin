package aftv

import "core:os/os2"
import "core:net"
import "core:time"
import "core:flags"
import "core:bytes"
import "core:strconv"
import "base:runtime"
import "core:mem/virtual"

import "shared:afmt"

status  :: afmt.ANSI24{fg = afmt.darkseagreen}
warning :: afmt.ANSI24{fg = afmt.khaki}
error   :: afmt.ANSI24{fg = afmt.indianred}
title   :: afmt.ANSI24{fg = afmt.black, bg = afmt.cornflowerblue, at = {.BOLD}}
data    :: afmt.ANSI24{fg = afmt.cornflowerblue}
label   :: afmt.ANSI24{fg = afmt.orchid}
notes   :: afmt.ANSI24{fg = afmt.cornflowerblue, at = {.ITALIC}}

to_bytes :: proc(s: string) -> ([]byte) {
	return transmute([]byte)(s)
}

exec :: proc(command: []string, allocator := context.allocator) -> (stdout: []byte) {
	state:  os2.Process_State
	error:  os2.Error
	stderr: []byte
	desc := os2.Process_Desc {command = command}
	state, stdout, stderr, error = os2.process_exec(desc, allocator)
	stdout = bytes.trim_right(stdout, {'\n'})
	stderr = bytes.trim_right(stderr, {'\n'})

	// print errors if they exist
	if len(stderr) != 0 {
		afmt.printfln("%s", warning, stderr)
	}
	if !state.success {
		afmt.printfln("%s: %s", error, desc.command[0], os2.error_string(error))
	}
	delete(stderr)
	return
}

connect :: proc(connect: net.Host_Or_Endpoint) -> (success: bool) {
	connection: string
	switch c in connect {
	case net.Host:
		connection = afmt.tprintf("%v%v%v", c.hostname, ":", c.port == 0 ? 5555 : c.port)
	case net.Endpoint:
		connection = afmt.tprintf("%v%v%v", net.address_to_string(c.address), ":", c.port == 0 ? 5555 : c.port)
	}

	stdout := exec({"adb", "connect",  connection})
	defer delete(stdout)

	if bytes.contains(stdout, to_bytes("connected")) {
		afmt.printfln("%s", status, stdout)
		return true
	}

	afmt.printfln("%s", error, stdout)
	return false
}

disconnect :: proc() {
	stdout := exec({"adb", "disconnect"})
	afmt.printfln("%s", status, stdout)
	delete(stdout)
}

Args :: struct {
	connect:    net.Host_Or_Endpoint `args:"name=c,pos=0,required" usage:"Default port is 5555."`,
	dumpsys:    string `args:"name=d" usage:"Device dumpsys info. Quote commands containing spaces."`,
	event:      string `args:"name=e" usage:"Execute event KEYCODE. Quote commands containing spaces."`,
	kill:       string `args:"name=k" usage:"Kill package name or 'all' (3rd Party) packages."`,
	launch:     string `args:"name=l" usage:"Launch package."`,
	memory:     string `args:"name=m" usage:"Memory usage of specified package."`,
	packages:   string `args:"name=p" usage:"Packages installed as either 'user' or 'system'."`,
	space:      string `args:"name=s" usage:"Space usage for either 'system' or specified package name."`,
	clearcache: string `args:"name=cc" usage:"Clear cache of specified package."`,
	cleardata:  string `args:"name=cd" usage:"Clear data of specified package."`,
	running:    bool   `args:"name=r" usage:"Running 3rd party applications."`,
	version:    bool   `args:"name=v" usage:"Version information."`,
}

print_usage :: proc() {
	using afmt, time
	usage := "./aftv c [-cc] [-cd] [-d] [-e] [-k] [-l] [-m] [-p] [-r] [-s] [-v]"
	flags := [][]string {
		{"-c:<host>, required", "Default port is 5555."},
		{"-cc:<string>"       , "Clear cache of specified package."},
		{"-cd:<string>"       , "Clear data of specified package."},
  	{"-d:<string>"        , "Device dumpsys info. Quote commands containing spaces."},
  	{"-e:<string>"        , "Execute event KEYCODE. Quote commands containing spaces."},
  	{"-k:<string>"        , "Kill package name or 'all' (3rd Party) packages."},
  	{"-l:<string>"        , "Launch package."},
  	{"-m:<string>"        , "Memory usage of specified package."},
  	{"-p:<string>"        , "Packages installed as either 'user' or 'system'."},
  	{"-r"                 , "Running 3rd party applications."},
  	{"-s:<string>"        , "Space usage for either 'system' or specified package name."},
  	{"-v"                 , "Version information."},
	}
	row := [2]Column(ANSI24) {{20, .LEFT, {fg = orange}},	{60, .LEFT, {fg = crimson}}}
	buf: [MIN_YYYY_DATE_LEN]u8
	printrow(row, ODIN_BUILD_PROJECT_NAME + " by:", "xuul the terror dog")
	printrow(row, "Compile Date:", to_string_yyyy_mm_dd(now(), buf[:]))
	printrow(row, "Odin Version:", ODIN_VERSION); println()
	printrow(row, "Usage:", usage);	println()
	for f in flags { printrow(row, f[:]) }
}

parse_args :: proc(args: ^Args) ->(ok: bool) {
	#partial switch err in flags.parse(args, os2.args[1:]) {
	case flags.Help_Request:
		print_usage()
		return false
	case flags.Validation_Error:
		afmt.printfln("%v", error, err)
		print_usage()
		return false
	}
	return true
}

main :: proc() {
	using afmt

	args:  Args
	varena: virtual.Arena
	arena := virtual.arena_allocator(&varena)

	if parse_args(&args) && connect(args.connect) {

		if args.clearcache != "" {
			printfln("%s %s", notes, "Attempting to clear cache of:", args.clearcache)
			cleared := exec({"adb", "shell", "pm", "clear", "--cache-only", args.clearcache}, arena)
		}

		if args.cleardata != "" {
			printfln("%s %s", notes, "Attempting to clear data of:", args.cleardata)
			cleared := exec({"adb", "shell", "pm", "clear", args.cleardata}, arena)
		}
		
		if args.dumpsys != "" {
			sysinfo := exec({"adb", "shell", "-x", "dumpsys", args.dumpsys}, arena)
			printfln("%s", data, sysinfo)
		}

		if args.event != "" {
			printfln("%s %s", notes, "Attempting to execute keyevent:", args.event)
			event := exec({"adb", "shell", "input", "keyevent", args.event})
		}

		if args.launch != "" {
			launch: []byte
			if args.launch == "org.xbmc.kodi" {
				launch = exec({"adb", "shell", "am", "start", "org.xbmc.kodi/.Splash"}, arena)
			} else {
				launch = exec({"adb", "shell", "am", "start", args.launch}, arena)
			}
			printfln("%s", data, launch)
		}

		if args.kill == "all" {
			packages := exec({"adb", "shell", "pm", "list", "packages", "-3"}, arena)
			running  := exec({"adb", "shell", "ps", "-o", "ARGS=CMD"}, arena)
			list1, _ := bytes.remove_all(packages, to_bytes("package:"), arena)
			list2    := bytes.split(running, {'\n'}, arena)
			for e in list2 {
				if !bytes.contains(e, to_bytes("com.amazon.tv")) && bytes.contains(list1, e) {
					printfln("%s %s", notes, "Killing:", e)
					dead := exec({"adb", "shell", "am", "force-stop", string(e)}, arena)
				}
			}
		} else if args.kill != "" {
			printfln("%s %s", notes, "Attempting to kill:", args.kill)
			dead := exec({"adb", "shell", "am", "force-stop", args.kill}, arena)
		}

		if args.memory != "" {
			usage := exec({"adb", "shell", "dumpsys", "meminfo", args.memory}, arena)
			if bytes.contains(usage, to_bytes("No process found")) {
				printfln("%s", warning, usage)
			} else {
				printfln("%s %s", title, "Memory Usage:", args.memory)
				printfln("%s", data, usage)
			}
		}

		switch args.packages {
		case "user":
			packages := exec({"adb", "shell", "pm", "list", "packages", "-3"}, arena)
			list1, _ := bytes.remove_all(packages, to_bytes("package:"), arena)
			list2    := bytes.split(list1, {'\n'}, arena)
			printfln("%s", title, "User Installed (3rd Party) Packages:")
			for e in list2 {
				if !bytes.contains(e, to_bytes("com.amazon.tv")) { printfln("%s", data, e) }
			}
		case "system":
			packages := exec({"adb", "shell", "pm", "list", "packages", "-s"}, arena)
			list, _  := bytes.remove_all(packages, to_bytes("package:"), arena)
			printfln("%s", title, "System Installed (FireOS) Packages:")
			printfln("%s", data, list)
		}

		if args.running {
			packages := exec({"adb", "shell", "pm", "list", "packages", "-3"}, arena)
			running  := exec({"adb", "shell", "ps", "-o", "ARGS=CMD"}, arena)
			list1, _ := bytes.remove_all(packages, to_bytes("package:"), arena)
			list2    := bytes.split(running, {'\n'}, arena)
			printfln("%s", title, "Running User Installed (3rd Party) Packages:")
			for e in list2 {
				if !bytes.contains(e, to_bytes("com.amazon.tv")) && bytes.contains(list1, e) {
					printfln("%s", data, e)
				}
			}
		}

		if args.space == "system" {
			diskstats := exec({"adb", "shell", "dumpsys", "diskstats"}, arena)
			print_system_stats(diskstats, arena)
		} else if args.space != "" {
			diskstats := exec({"adb", "shell", "dumpsys", "diskstats"}, arena)
			print_package_usage(diskstats, args.space, arena)
		}

		if args.version {
			android := exec({"adb", "shell", "getprop", "ro.build.version.release"}, arena)
			fireos  := exec({"adb", "shell", "getprop", "ro.build.version.name"}, arena)
			model   := exec({"adb", "shell", "getprop", "ro.product.oemmodel"}, arena)
			serial  := exec({"adb", "shell", "getprop", "ro.serialno"}, arena)
			row := [2]Column(ANSI24) {{18, .LEFT, label}, {42, .LEFT, data}}
			printrow(row, "Android Version:", string(android))
			printrow(row, "FireOS Version:", string(fireos))
			printrow(row, "Device Model:", string(model))
			printrow(row, "Serial No:", string(serial))
		}

		virtual.arena_destroy(&varena)
		disconnect()
	}
}

print_system_stats :: proc(diskstats: []byte, allocator := context.allocator) {
	lines := bytes.split(diskstats, {'\n'}, allocator)
	for line, idx in lines {
		switch idx {
		case 00..=01: print_speed_metrics(line, idx)
		case 02..=04: print_system_usage(line, idx, allocator)
		case 05..=13: print_categorical_usage(line, idx, allocator)
		case: break
		}
	}
}

print_speed_metrics :: proc(line: []byte, index: int) {
	using afmt
	title := [2]Column(ANSI24) {{17, .LEFT, title}, {63, .LEFT, title}}
	row   := [2]Column(ANSI24) {{17, .LEFT, label}, {63, .LEFT, data}}
	if index == 0 {
		printrow(title, "Speed", "Disk Metrics")
		printrow(row, "Latency:", string(line[len("Latency: "):]))
	} else if index == 1 {
		printrow(row, "Write:", tprint(string(line[len("Recent Disk Write Speed (kB/s) = "):]), "kB/s"))
	}
}

print_system_usage :: proc(line: []byte, index: int, allocator := context.allocator) {
	using afmt
	title := [2]Column(ANSI24) {{17, .LEFT, title}, {63, .LEFT, title}}
	row := [10]Column(ANSI24) {
		{17, .LEFT,  label}, {10, .RIGHT, data}, {10, .RIGHT, data}, {03, .RIGHT, data}, {12, .RIGHT, data},
		{11, .RIGHT, data }, {06, .RIGHT, data}, {02, .RIGHT, data}, {04, .RIGHT, data}, {05, .RIGHT, data},
	}
	split := bytes.split(line, {' '}, allocator)
	data  := make([dynamic]string, allocator = allocator)
	for s in split {
		if len(s) > 0 && s[len(s)-1] == 'K' {
			if num, num_ok := strconv.parse_f64(string(s[:len(s)-1])); num_ok {
				append(&data, tprintf("%.2f%s", num / 1024, "MB"))
				append(&data, tprintf("%s%.2f%s", "(", num / 1048576, "GB)"))
			}
		}	else {
			append(&data, string(s))
		}
	}
	if index == 2 {
		printrow(title, "System", "Disk Usage")
	}
	if len(data) >= 10 {
		printrow(row, data[:])
	}
}

print_categorical_usage :: proc (line: []byte, index: int, allocator := context.allocator) {
	using afmt
	title := [2]Column(ANSI24) {{17, .LEFT, title}, {63, .LEFT, title}}
	row   := [3]Column(ANSI24) {{17, .LEFT, label}, {10, .RIGHT, data}, {10, .RIGHT, data}}
	split := bytes.split(line, {':', ' '}, allocator)
	data  := make([dynamic]string, 3, allocator = allocator)
	if num, num_ok := strconv.parse_f64(string(split[1])); num_ok {
		data[0] = tprintf("%s%s", split[0], ":")
		data[1] = tprintf("%.2f%s", num / 1048576, "MB")
		data[2] = tprintf("%s%.2f%s", "(", num / 1048576 / 1024, "GB)")
	}
	if index == 5 {
		printrow(title, "Categorical", "Disk Usage")
	}
	printrow(row, data[:])
}

print_package_usage :: proc (diskstats: []byte, pkg: string, allocator := context.allocator) {
	using afmt
	title := [2]Column(ANSI24) {{17, .LEFT, title}, {20, .LEFT, title}}
	row   := [3]Column(ANSI24) {{17, .LEFT, label}, {10, .RIGHT, data}, {10, .RIGHT, data}}
	lines := bytes.split(diskstats, {'\n'}, allocator)

	app_index := -1
	app_size:   f64
	data_size:  f64
	cache_size: f64

	packages:    [][]byte
	app_sizes:   [][]byte
	data_sizes:  [][]byte
	cache_sizes: [][]byte

	for line in lines {
		if bytes.contains(line, to_bytes("Package Names: ")) {
			packages = bytes.split(line[len("Package Names: "):], {','}, allocator)
			for p, i in packages {
				if bytes.contains(p, to_bytes(pkg)) { app_index = i }
			}
		}
		if bytes.contains(line, to_bytes("App Sizes: ")) {
			app_sizes = bytes.split(line[len("App Sizes: "):], {','}, allocator)
		}
		if bytes.contains(line, to_bytes("App Data Sizes: ")) {
			data_sizes = bytes.split(line[len("App Data Sizes: "):], {','}, allocator)
		}
		if bytes.contains(line, to_bytes("Cache Sizes: ")) {
			cache_sizes = bytes.split(line[len("Cache Sizes: "):], {','}, allocator)
		}
	}

	if app_index > 0 {
		app_size, _   = strconv.parse_f64(string(app_sizes[app_index][:]))
		data_size, _  = strconv.parse_f64(string(data_sizes[app_index][:]))
		cache_size, _ = strconv.parse_f64(string(cache_sizes[app_index][:]))
	}

	app_mb   := tprintf("%.2f%s", app_size / 1048576, "MB")
	app_gb   := tprintf("%s%.2f%s", "(", app_size / 1048576 / 1024, "GB)")
	data_mb  := tprintf("%.2f%s", data_size / 1048576, "MB")
	data_gb  := tprintf("%s%.2f%s", "(", data_size / 1048576 / 1024, "GB)")
	cache_mb := tprintf("%.2f%s", cache_size / 1048576, "MB")
	cache_gb := tprintf("%s%.2f%s", "(", cache_size / 1048576 / 1024, "GB)")

	printrow(title, "Disk Usage of:", pkg)
	printrow(row, "App Size:", app_mb, app_gb)
	printrow(row, "Data Size:", data_mb, data_gb)
	printrow(row, "Cache Size:", cache_mb, cache_gb)
}