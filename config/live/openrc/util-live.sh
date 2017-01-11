#!/bin/bash
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

kernel_cmdline(){
	for param in $(cat /proc/cmdline); do
		case "${param}" in
			$1=*) echo "${param##*=}"; return 0 ;;
			$1) return 0 ;;
			*) continue ;;
		esac
	done
	[ -n "${2}" ] && echo "${2}"
	return 1
}

get_country(){
	echo $(kernel_cmdline lang)
}

get_keyboard(){
	echo $(kernel_cmdline keytable)
}

get_layout(){
	echo $(kernel_cmdline layout)
}

get_timer_ms(){
	echo $(date +%s%3N)
}

# $1: start timer
elapsed_time_ms(){
	echo $(echo $1 $(get_timer_ms) | awk '{ printf "%0.3f",($2-$1)/1000 }')
}


find_legacy_keymap(){
	file="${DATADIR}/kbd-model.map"
	while read -r line || [[ -n $line ]]; do
		if [[ -z $line ]] || [[ $line == \#* ]]; then
			continue
		fi

		mapping=( $line ); # parses columns
		if [[ ${#mapping[@]} != 5 ]]; then
			continue
		fi

		if  [[ "$KEYMAP" != "${mapping[0]}" ]]; then
			continue
		fi

		if [[ "${mapping[3]}" = "-" ]]; then
			mapping[3]=""
		fi

		X11_LAYOUT=${mapping[1]}
		X11_MODEL=${mapping[2]}
		X11_VARIANT=${mapping[3]}
		x11_OPTIONS=${mapping[4]}
	done < $file
}

write_x11_config(){
	# find a x11 layout that matches the keymap
	# in isolinux if you select a keyboard layout and a language that doesnt match this layout,
	# it will provide the correct keymap, but not kblayout value
	local X11_LAYOUT=
	local X11_MODEL="pc105"
	local X11_VARIANT=""
	local X11_OPTIONS="terminate:ctrl_alt_bksp"

	find_legacy_keymap

	# layout not found, use KBLAYOUT
	if [[ -z "$X11_LAYOUT" ]]; then
		X11_LAYOUT="$KBLAYOUT"
	fi

	# create X11 keyboard layout config
	mkdir -p "/etc/X11/xorg.conf.d"

	local XORGKBLAYOUT="/etc/X11/xorg.conf.d/00-keyboard.conf"

	echo "" >> "$XORGKBLAYOUT"
	echo "Section \"InputClass\"" > "$XORGKBLAYOUT"
	echo " Identifier \"system-keyboard\"" >> "$XORGKBLAYOUT"
	echo " MatchIsKeyboard \"on\"" >> "$XORGKBLAYOUT"
	echo " Option \"XkbLayout\" \"$X11_LAYOUT\"" >> "$XORGKBLAYOUT"
	echo " Option \"XkbModel\" \"$X11_MODEL\"" >> "$XORGKBLAYOUT"
	echo " Option \"XkbVariant\" \"$X11_VARIANT\"" >> "$XORGKBLAYOUT"
	echo " Option \"XkbOptions\" \"$X11_OPTIONS\"" >> "$XORGKBLAYOUT"
	echo "EndSection" >> "$XORGKBLAYOUT"
}

configure_language(){
	# hack to be able to set the locale on bootup
	local LOCALE=$(get_country)
	local KEYMAP=$(get_keyboard)
	local KBLAYOUT=$(get_layout)

	# this is needed for efi, it doesn't set any cmdline
	[[ -z "$LOCALE" ]] && LOCALE="en_US"
	[[ -z "$KEYMAP" ]] && KEYMAP="us"
	[[ -z "$KBLAYOUT" ]] && KBLAYOUT="us"

	local TLANG=${LOCALE%.*}

	sed -i -r "s/#(${TLANG}.*UTF-8)/\1/g" /etc/locale.gen

	echo "LANG=${LOCALE}.UTF-8" >> /etc/environment

	if [[ -f /usr/bin/openrc ]]; then
		sed -i "s/keymap=.*/keymap=\"${KEYMAP}\"/" /etc/conf.d/keymaps
	fi
	echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
	echo "LANG=${LOCALE}.UTF-8" > /etc/locale.conf

	write_x11_config

	loadkeys "${KEYMAP}"

	locale-gen ${TLANG}
}

configure_clock(){
    if [[ -d /run/openrc ]];then
        ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
        echo "Europe/London" > /etc/timezone
    fi
}


configure_sudoers_d(){
	echo "%wheel  ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/g_wheel
	echo "root ALL=(ALL) ALL"  > /etc/sudoers.d/u_root
	#echo "${username} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/u_live
}

configure_swap(){
	local swapdev="$(fdisk -l 2>/dev/null | grep swap | cut -d' ' -f1)"
	if [ -e "${swapdev}" ]; then
		swapon ${swapdev}
	fi
}


