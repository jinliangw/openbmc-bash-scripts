#!/bin/sh

# -----------------------------------------------------------------------------
# Helper: Safe file reading
# Checks if file exists to avoid "No such file" shell errors during redirection
# -----------------------------------------------------------------------------
read_val() {
    if [ -f "$1" ]; then
        read -r val < "$1"
        echo "$val"
    fi
}

# -----------------------------------------------------------------------------
# Helper: Get standard USB speed string
# -----------------------------------------------------------------------------
get_speed_str() {
    case "$1" in
        "1.5") echo "1.5M" ;;
        "12")  echo "12M" ;;
        "480") echo "480M" ;;
        "5000") echo "5000M" ;;
        "10000") echo "10000M" ;;
        "") echo "" ;;
        *) echo "${1}M" ;;
    esac
}

# -----------------------------------------------------------------------------
# Recursive Walk Function
# -----------------------------------------------------------------------------
walk_usb() {
    local syspath="$1"
    local indent="$2"
    local bus_id="$3"

    # 1. READ DEVICE INFO 
    local devnum=$(read_val "$syspath/devnum")
    local class=$(read_val "$syspath/bDeviceClass")
    local speed_raw=$(read_val "$syspath/speed")
    local speed=$(get_speed_str "$speed_raw")
    local vendor=$(read_val "$syspath/idVendor")
    local product=$(read_val "$syspath/idProduct")
    local devname="${syspath##*/}"

    # Format speed string for display
    local speed_display=""
    [ -n "$speed" ] && speed_display=", $speed"

    # 2. DETERMINE PORT & DRIVER
    local port=""
    local driver=""

    if [ "${devname%%[0-9]*}" = "usb" ]; then
        # Root Hub
        port="1"
        local parent_driver=$(readlink "$syspath/../driver")
        driver="${parent_driver##*/}"

        printf "/:  Bus %02d.Port %s: Dev %s, Class=root_hub, Driver=%s/%s\n" \
            "$bus_id" "$port" "$devnum" "$driver" "$speed"
    else
        # Child Device
        port="${devname##*.}" 
        [ "$port" = "$devname" ] && port="${devname##*-}"

        local drv_link=$(readlink "$syspath/driver")
        driver="${drv_link##*/}"

        printf "%s|__ Port %s: Dev %s, Class=%s, Driver=%s%s\n" \
            "$indent" "$port" "$devnum" "$class" "${driver:-<none>}" "$speed_display"
    fi

    # 3. PRINT VERBOSE INFO (-v)
    if [ "$SHOW_VERBOSE" = "true" ]; then
        # Only read strings if they exist to prevent errors
        local manuf=$(read_val "$syspath/manufacturer")
        local prod=$(read_val "$syspath/product")

        # Only print ID line if we actually have VIDs/PIDs
        if [ -n "$vendor" ]; then
            printf "%s    ID %s:%s %s %s\n" "$indent" "$vendor" "$product" "$manuf" "$prod"
        fi
    fi

    # 4. HANDLE INTERFACES
    for intf_path in "$syspath/$devname":*; do
        [ -e "$intf_path" ] || continue
        local intf_class=$(read_val "$intf_path/bInterfaceClass")
        local intf_drv_link=$(readlink "$intf_path/driver")
        local intf_driver="${intf_drv_link##*/}"
        local intf_idx="${intf_path##*.}"

        if [ -n "$intf_driver" ] || [ "$SHOW_VERBOSE" = "true" ]; then
            printf "%s    |__ Intf %s, Class=%s, Driver=%s\n" \
                "$indent" "$intf_idx" "$intf_class" "${intf_driver:-<no driver>}"
        fi
    done

    # 5. RECURSE
    for child in "$syspath"/*; do
        [ -d "$child" ] || continue
        local child_name="${child##*/}"

        # Filter: Start with BusID, contain dash, NO colon
        case "$child_name" in 
            "$bus_id-"* )
                if ! echo "$child_name" | grep -q ":"; then
                    walk_usb "$child" "$indent    " "$bus_id"
                fi
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
SHOW_VERBOSE=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        -v) SHOW_VERBOSE=true ;;
        -t) ;; 
        *) ;;
    esac
    shift
done

for root in /sys/bus/usb/devices/usb*; do
    [ -e "$root" ] || continue
    phy_path=$(readlink -f "$root")
    bus_num=$(read_val "$root/busnum")
    walk_usb "$phy_path" "" "$bus_num"
done
