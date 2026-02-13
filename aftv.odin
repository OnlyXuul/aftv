package aftv

import "core:os"
import "core:net"
import "core:time"
import "core:flags"
import "core:bytes"
import "core:strconv"
import "base:runtime"
import "core:reflect"
import "core:mem/virtual"

import "shared:afmt"

PACKAGE :: ODIN_BUILD_PROJECT_NAME

status  := afmt.ANSI24{fg = afmt.darkseagreen}
warning := afmt.ANSI24{fg = afmt.khaki}
error   := afmt.ANSI24{fg = afmt.indianred}
title   := afmt.ANSI24{fg = afmt.black, bg = afmt.cornflowerblue, at = {.BOLD}}
data    := afmt.ANSI24{fg = afmt.cornflowerblue}
label   := afmt.ANSI24{fg = afmt.orchid}
notes   := afmt.ANSI24{fg = afmt.cornflowerblue, at = {.ITALIC}}

no_color_bold   := afmt.ANSI3{at = {.BOLD}}
no_color_italic := afmt.ANSI3{at = {.ITALIC}}

_bytes :: proc(s: string) -> []byte {	return transmute([]byte)(s) }

exec :: proc(command: []string, allocator := context.allocator) -> []byte {
	desc := os.Process_Desc {command = command}
	state, stdout, stderr, error := os.process_exec(desc, allocator)
	stdout = bytes.trim_right(stdout, {'\n'})
	stderr = bytes.trim_right(stderr, {'\n'})
	if len(stderr) != 0 {
		afmt.printfln("%s", warning, stderr)
	}
	if !state.success {
		afmt.printfln("%s: %s", error, desc.command[0], os.error_string(error))
	}
	if allocator == context.allocator { delete(stderr) }
	return stdout
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

	if bytes.contains(stdout, _bytes("connected")) {
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

shell :: proc(allocator: runtime.Allocator) {
	desc := os.Process_Desc {
		command = {"adb", "shell"},
		stderr  = os.stderr,
		stdout  = os.stdout,
		stdin   = os.stdin,
	}

	desc.env = os.environ(allocator) or_else nil

	afmt.set("-f[255,216,1]")
	if process, p_err := os.process_start(desc); p_err != nil {
		afmt.println(error, "Process start:", p_err)
	} else {
		if _, w_err := os.process_wait(process); w_err != nil {
			afmt.println(error, "Process wait:", w_err)
		}
		if c_err := os.process_close(process); c_err != nil {
			afmt.println(error, "Process close:", c_err)
		}
	}
	afmt.reset()
}

Args :: struct {
	connect:    net.Host_Or_Endpoint `args:"name=c,pos=0,required" usage:"Default port is 5555 if not provided."`,
	clearcache: string `args:"name=cc" usage:"Clear cache of specified package."`,
	cleardata:  string `args:"name=cd" usage:"Clear data of specified package."`,
	dumpsys:    string `args:"name=d"  usage:"Device dumpsys info. Quote commands containing spaces."`,
	event:      string `args:"name=e"  usage:"Execute event KEYCODE. Quote commands containing spaces."`,
	kill:       string `args:"name=k"  usage:"Kill package name or 'all' (3rd Party) packages."`,
	launch:     string `args:"name=l"  usage:"Launch package."`,
	memory:     string `args:"name=m"  usage:"Memory usage of 'system' or specified package."`,
	packages:   string `args:"name=p"  usage:"Packages installed as either 'user' or 'system'."`,
	running:    bool   `args:"name=r"  usage:"Running 3rd party applications."`,
	shell:      bool   `args:"name=s"  usage:"Enter adb shell"`,
	usage:      string `args:"name=u"  usage:"Disk usage of 'system' or specified package name."`,
	version:    bool   `args:"name=v"  usage:"Version information."`,
}

usage_tag :: proc(tags: []reflect.Struct_Tag, name: string) -> (usage: string ) {
	loop: for t in tags {
		if args, a_ok := reflect.struct_tag_lookup(t, "args"); a_ok {
			if sub_name, s_ok := flags.get_subtag(args, "name"); s_ok {
				if sub_name == name {
					if _usage, u_ok := reflect.struct_tag_lookup(t, "usage"); u_ok {
						usage = _usage
					}
					break loop
				}
			}
		}
	}
	return
}

//write_usage(os2.to_stream(os2.stdout), Args, ODIN_BUILD_PROJECT_NAME)

usage :: proc() {
	tags := reflect.struct_field_tags(Args)
	buf: [time.MIN_YYYY_DATE_LEN]u8
	usage := [][]string {
		{PACKAGE + " by:", "xuul the terror dog"},
		{"Compile Date:",  time.to_string_yyyy_mm_dd(time.now(), buf[:])},
		{"Odin Version:",  ODIN_VERSION},
		{"",""},
		{"Usage:", "aftv c [-cc] [-cd] [-d] [-e] [-k] [-l] [-m] [-p] [-r] [-s] [-u] [-v]"},
		{"",""},
		{"-c:<host|ip>[:port]", usage_tag(tags, "c")},
		{"-cc:<string>"       , usage_tag(tags, "cc")},
		{"-cd:<string>"       , usage_tag(tags, "cd")},
  	{"-d:<string>"        , usage_tag(tags, "d")},
  	{"-e:<string>"        , usage_tag(tags, "e")},
  	{"-k:<string>"        , usage_tag(tags, "k")},
  	{"-l:<string>"        , usage_tag(tags, "l")},
  	{"-m:<string>"        , usage_tag(tags, "m")},
  	{"-p:<string>"        , usage_tag(tags, "p")},
  	{"-r"                 , usage_tag(tags, "r")},
		{"-s"                 , usage_tag(tags, "s")},
  	{"-u:<string>"        , usage_tag(tags, "u")},
  	{"-v"                 , usage_tag(tags, "v")},
	}
	cols: [2]afmt.Column(afmt.ANSI24)
	cols = {{20, .LEFT, {fg = afmt.orange}}, {80, .LEFT, {fg = afmt.crimson}}}
	afmt.printtable(cols, usage)
}

parse :: proc(args: ^Args) -> (ok: bool) {
	switch err in flags.parse(args, os.args[1:]) {
	case flags.Help_Request:     usage()
	case flags.Validation_Error: afmt.printfln("%v", error, err.message)
	case flags.Parse_Error:      afmt.printfln("%v", error, err.message)
	case flags.Open_File_Error:  afmt.printfln("%v", error, err)
	case: ok = true
	}
	return
}

main :: proc() {
	args: Args
	virt: virtual.Arena
	arena := virtual.arena_allocator(&virt)

	if parse(&args) && connect(args.connect) {

		if args.clearcache != "" {
			afmt.printfln("%s %s", notes, "Attempting to clear cache of:", args.clearcache)
			cleared := exec({"adb", "shell", "pm", "clear", "--cache-only", args.clearcache}, arena)
		}

		if args.cleardata != "" {
			afmt.printfln("%s %s", notes, "Attempting to clear data of:", args.cleardata)
			cleared := exec({"adb", "shell", "pm", "clear", args.cleardata}, arena)
		}
		
		if args.dumpsys != "" {
			sysinfo := exec({"adb", "shell", "-x", "dumpsys", args.dumpsys}, arena)
			afmt.printfln("%s", data, sysinfo)
		}

		if args.event != "" {
			afmt.printfln("%s %s", notes, "Attempting to execute keyevent:", args.event)
			event := exec({"adb", "shell", "input", "keyevent", args.event})
		}

		if args.launch != "" {
			launch: []byte
			if args.launch == "org.xbmc.kodi" {
				launch = exec({"adb", "shell", "am", "start", "org.xbmc.kodi/.Splash"}, arena)
			} else {
				launch = exec({"adb", "shell", "am", "start", args.launch}, arena)
			}
			afmt.printfln("%s", data, launch)
		}

		if args.kill == "all" {
			packages := exec({"adb", "shell", "pm", "list", "packages", "-3"}, arena)
			running  := exec({"adb", "shell", "ps", "-o", "ARGS=CMD"}, arena)
			list1, _ := bytes.remove_all(packages, _bytes("package:"), arena)
			list2    := bytes.split(running, {'\n'}, arena)
			for e in list2 {
				if !bytes.contains(e, _bytes("com.amazon.tv")) && bytes.contains(list1, e) {
					afmt.printfln("%s %s", notes, "Killing:", e)
					dead := exec({"adb", "shell", "am", "force-stop", string(e)}, arena)
				}
			}
		} else if args.kill != "" {
			afmt.printfln("%s %s", notes, "Attempting to kill:", args.kill)
			dead := exec({"adb", "shell", "am", "force-stop", args.kill}, arena)
		}

		if args.memory == "system" || args.memory == "sys" {
			usage := exec({"adb", "shell", "dumpsys", "meminfo"}, arena)
			afmt.printfln("%s %s", title, "Memory Usage:", "System")
			afmt.printfln("%s", data, usage)
		} else if args.memory != "" {
			usage := exec({"adb", "shell", "dumpsys", "meminfo", args.memory}, arena)
			if bytes.contains(usage, _bytes("No process found")) {
				afmt.printfln("%s", warning, usage)
			} else {
				afmt.printfln("%s %s", title, "Memory Usage:", args.memory)
				afmt.printfln("%s", data, usage)
			}
		}

		if  args.packages == "user" {
			packages := exec({"adb", "shell", "pm", "list", "packages", "-3"}, arena)
			list1, _ := bytes.remove_all(packages, _bytes("package:"), arena)
			list2    := bytes.split(list1, {'\n'}, arena)
			afmt.printfln("%s", title, "User Installed (3rd Party) Packages:")
			for e in list2 {
				if !bytes.contains(e, _bytes("com.amazon.tv")) { afmt.printfln("%s", data, e) }
			}
		} else if args.packages == "system" || args.packages == "sys" {
			packages := exec({"adb", "shell", "pm", "list", "packages", "-s"}, arena)
			list, _  := bytes.remove_all(packages, _bytes("package:"), arena)
			afmt.printfln("%s", title, "System Installed (FireOS) Packages:")
			afmt.printfln("%s", data, list)
		}

		if args.running {
			packages := exec({"adb", "shell", "pm", "list", "packages", "-3"}, arena)
			running  := exec({"adb", "shell", "ps", "-o", "ARGS=CMD"}, arena)
			list1, _ := bytes.remove_all(packages, _bytes("package:"), arena)
			list2    := bytes.split(running, {'\n'}, arena)
			afmt.printfln("%s", title, "Running User Installed (3rd Party) Packages:")
			for e in list2 {
				if !bytes.contains(e, _bytes("com.amazon.tv")) && bytes.contains(list1, e) {
					afmt.printfln("%s", data, e)
				}
			}
		}

		if args.shell {
			afmt.println(afmt.ANSI24{fg = afmt.RGB{249, 86, 2}}, "Starting ADB shell ...")
			shell(arena)
		}

		if args.usage == "system" || args.usage == "sys" {
			diskstats := exec({"adb", "shell", "dumpsys", "diskstats"}, arena)
			print_system_usage(diskstats, arena)
		} else if args.usage != "" {
			diskstats := exec({"adb", "shell", "dumpsys", "diskstats"}, arena)
			print_package_usage(diskstats, args.usage, arena)
		}

		if args.version {
			android := exec({"adb", "shell", "getprop", "ro.build.version.release"}, arena)
			fireos  := exec({"adb", "shell", "getprop", "ro.build.version.name"}, arena)
			model   := exec({"adb", "shell", "getprop", "ro.product.oemmodel"}, arena)
			serial  := exec({"adb", "shell", "getprop", "ro.serialno"}, arena)
			cols := [2]afmt.Column(afmt.ANSI24) {{18, .LEFT, label}, {42, .LEFT, data}}
			afmt.printrow(cols, "Android Version:", string(android))
			afmt.printrow(cols, "FireOS Version:", string(fireos))
			afmt.printrow(cols, "Device Model:", string(model))
			afmt.printrow(cols, "Serial No:", string(serial))
		}

		virtual.arena_destroy(&virt)
		disconnect()
	}
}

print_system_usage :: proc(diskstats: []byte, allocator: runtime.Allocator) {
	lines := bytes.split(diskstats, {'\n'}, allocator)
	for line, idx in lines {
		switch idx {
		case 00..=01: print_disk_speed(line, idx)
		case 02..=04: print_disk_usage(line, idx, allocator)
		case 05..=13: print_group_usage(line, idx, allocator)
		case: break
		}
	}

	print_disk_speed :: proc(line: []byte, index: int) {
		title := [2]afmt.Column(afmt.ANSI24) {{17, .LEFT, title}, {63, .LEFT, title}}
		cols  := [2]afmt.Column(afmt.ANSI24) {{17, .LEFT, label}, {63, .LEFT, data}}
		if index == 0 {
			afmt.printrow(title, "Speed", "Disk Metrics")
			afmt.printrow(cols, "Latency:", string(line[len("Latency: "):]))
		} else if index == 1 {
			afmt.printrow(cols, "Write:", afmt.tprint(string(line[len("Recent Disk Write Speed (kB/s) = "):]), "kB/s"))
		}
	}

	print_disk_usage :: proc(line: []byte, index: int, allocator: runtime.Allocator) {
		title := [2]afmt.Column(afmt.ANSI24) {{17, .LEFT, title}, {63, .LEFT, title}}
		cols  := [10]afmt.Column(afmt.ANSI24) {
			{17, .LEFT,  label}, {10, .RIGHT, data}, {10, .RIGHT, data}, {03, .RIGHT, data}, {12, .RIGHT, data},
			{11, .RIGHT, data }, {06, .RIGHT, data}, {02, .RIGHT, data}, {04, .RIGHT, data}, {05, .RIGHT, data},
		}
		split := bytes.split(line, {' '}, allocator)
		data  := make([dynamic]string, allocator = allocator)
		for s in split {
			if len(s) > 0 && s[len(s)-1] == 'K' {
				if num, num_ok := strconv.parse_f64(string(s[:len(s)-1])); num_ok {
					append(&data, afmt.tprintf("%.2f%s", num / 1024, "MB"))
					append(&data, afmt.tprintf("%s%.2f%s", "(", num / 1048576, "GB)"))
				}
			}	else {
				append(&data, string(s))
			}
		}
		if index == 2 {
			afmt.printrow(title, "System", "Disk Usage")
		}
		if len(data) >= 10 {
			afmt.printtable(cols, data)
		}
	}

	print_group_usage :: proc (line: []byte, index: int, allocator: runtime.Allocator) {
		title := [2]afmt.Column(afmt.ANSI24) {{17, .LEFT, title}, {63, .LEFT, title}}
		cols  := [3]afmt.Column(afmt.ANSI24) {{17, .LEFT, label}, {10, .RIGHT, data}, {10, .RIGHT, data}}
		split := bytes.split(line, {':', ' '}, allocator)
		data  := make([dynamic]string, 3, allocator = allocator)
		if num, num_ok := strconv.parse_f64(string(split[1])); num_ok {
			data[0] = afmt.tprintf("%s%s", split[0], ":")
			data[1] = afmt.tprintf("%.2f%s", num / 1048576, "MB")
			data[2] = afmt.tprintf("%s%.2f%s", "(", num / 1048576 / 1024, "GB)")
		}
		if index == 5 {
			afmt.printrow(title, "Categorical", "Disk Usage")
		}
		afmt.printtable(cols, data)
	}
}

print_package_usage :: proc (diskstats: []byte, pkg: string, allocator: runtime.Allocator) {
	title := [2]afmt.Column(afmt.ANSI24) {{17, .LEFT, title}, {20, .LEFT, title}}
	cols  := [3]afmt.Column(afmt.ANSI24) {{17, .LEFT, label}, {10, .RIGHT, data}, {10, .RIGHT, data}}
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
		if bytes.contains(line, _bytes("Package Names: ")) {
			packages = bytes.split(line[len("Package Names: "):], {','}, allocator)
			for p, i in packages {
				if bytes.contains(p, _bytes(pkg)) { app_index = i }
			}
		}
		if bytes.contains(line, _bytes("App Sizes: ")) {
			app_sizes = bytes.split(line[len("App Sizes: "):], {','}, allocator)
		}
		if bytes.contains(line, _bytes("App Data Sizes: ")) {
			data_sizes = bytes.split(line[len("App Data Sizes: "):], {','}, allocator)
		}
		if bytes.contains(line, _bytes("Cache Sizes: ")) {
			cache_sizes = bytes.split(line[len("Cache Sizes: "):], {','}, allocator)
		}
	}

	if app_index > 0 {
		app_size, _   = strconv.parse_f64(string(app_sizes[app_index][:]))
		data_size, _  = strconv.parse_f64(string(data_sizes[app_index][:]))
		cache_size, _ = strconv.parse_f64(string(cache_sizes[app_index][:]))
	}

	app_mb   := afmt.tprintf("%.2f%s", app_size / 1048576, "MB")
	app_gb   := afmt.tprintf("%s%.2f%s", "(", app_size / 1048576 / 1024, "GB)")
	data_mb  := afmt.tprintf("%.2f%s", data_size / 1048576, "MB")
	data_gb  := afmt.tprintf("%s%.2f%s", "(", data_size / 1048576 / 1024, "GB)")
	cache_mb := afmt.tprintf("%.2f%s", cache_size / 1048576, "MB")
	cache_gb := afmt.tprintf("%s%.2f%s", "(", cache_size / 1048576 / 1024, "GB)")

	afmt.printrow(title, "Disk Usage of:", pkg)
	afmt.printrow(cols, "App Size:", app_mb, app_gb)
	afmt.printrow(cols, "Data Size:", data_mb, data_gb)
	afmt.printrow(cols, "Cache Size:", cache_mb, cache_gb)
}