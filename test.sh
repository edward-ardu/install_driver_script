#!/usr/bin/bash
# hellods s

# test,delete when real use.
RED='\033[0;31m'
NC='\033[0m'

initAutodetect() {
    array=()
    arr_subscript=0
    InstallName=
    SenorId=
    OpenCameraName=
    BOOTCONFIG="/boot/config.txt"
    BIT=`getconf LONG_BIT`
    PWD_GET=`pwd`
}

# removeDtoverlay() {
#     sudo dtoverlay -r imx519>/dev/null 2>&1
#     sudo dtoverlay -r arducam>/dev/null 2>&1
#     sudo dtoverlay -r arducam_64mp>/dev/null 2>&1
# }

configCheck() {

    grepcmd i2cdetect
    if [ $? -ne 0 ]; then
        echo "Download i2c-tools."
        sudo apt install -y i2c-tools
    fi
    
    if ! grep -q "^i2c[-_]dev" /etc/modules; then
        sudo printf "i2c-dev\n" >>/etc/modules
        sudo modprobe i2c-dev
    fi
    

    if [ $(grep -c "dtparam=i2c_vc=on" "$BOOTCONFIG") -eq 0 ]; then
        sudo sed -i '$adtparam=i2c_vc=on' "$BOOTCONFIG"
        sudo sed -i '$adtparam=i2c_arm=on' "$BOOTCONFIG"
        echo "Already add 'dtparam=i2c_vc=on' and 'dtparam=i2c_arm=on' in /boot/config.txt"
        sudo dtparam i2c_vc
        sudo dtparam i2c_arm
    fi
    if [[ $(grep -c "^dtoverlay=imx519" "$BOOTCONFIG") -ne 0 \
    || $(grep -c "^dtoverlay=arducam" "$BOOTCONFIG") -ne 0 ]]; then
        echo "You have installed our driver and it works."
        echo "If you want to redetect the camera, you need to modify the /boot/config.txt file and reboot."
        echo "Do you agree to modify the file?(y/n):"
        read USER_INPUT
        case $USER_INPUT in
        'y'|'Y')
            echo "Changed"
            sudo sed 's/^\s*dtoverlay=imx519/#dtoverlay=imx519/g' -i $BOOTCONFIG
            sudo sed 's/^\s*dtoverlay=arducam/#dtoverlay=arducam/g' -i $BOOTCONFIG
            sudo sed 's/^\s*dtoverlay=arducam_64mp/#dtoverlay=arducam_64mp/g' -i $BOOTCONFIG
            
            echo "reboot now?(y/n):"
            read USER_INPUT
            case $USER_INPUT in
            'y'|'Y')
                echo "reboot"
                sudo reboot
            ;;
            *)
                echo "cancel"
                echo "Re-execution of the script will only take effect after restarting."
                exit -1
            ;;
            esac

        ;;
        *)
            echo "cancel"
            exit -1
        ;;
        esac

    fi
}

installFile() {
    
    CAMERA_I2C_FILE_NAME="camera_i2c"
    CAMERA_I2C_FILE_DOWNLOAD_LINK="https://raw.githubusercontent.com/ArduCAM/MIPI_Camera/master/RPI/utils/camera_i2c"
    RPI3_GPIOVIRTBUF_FILE_NAME="rpi3-gpiovirtbuf"

    if [ ! -s $CAMERA_I2C_FILE_NAME ]; then
        wget -O $CAMERA_I2C_FILE_NAME $CAMERA_I2C_FILE_DOWNLOAD_LINK
    fi
    if [ $? -ne 0 ]; then
        echo -e "${RED}Download failed.${NC}"
        echo "Please check your network and try again."
        exit -1
    else

    if [ "$BIT" = 32 ]; then
        RPI3_GPIOVIRTBUF_FILE_DOWNLOAD_LINK="https://github.com/ArduCAM/MIPI_Camera/raw/master/RPI/utils/rpi3-gpiovirtbuf/32/rpi3-gpiovirtbuf"
    elif [ "$BIT" = 64 ]; then
        RPI3_GPIOVIRTBUF_FILE_DOWNLOAD_LINK="https://github.com/ArduCAM/MIPI_Camera/raw/master/RPI/utils/rpi3-gpiovirtbuf/64/rpi3-gpiovirtbuf"
    fi

    if [ ! -s $RPI3_GPIOVIRTBUF_FILE_NAME ]; then
        wget -O $RPI3_GPIOVIRTBUF_FILE_NAME $RPI3_GPIOVIRTBUF_FILE_DOWNLOAD_LINK
    fi

    if [ $? -ne 0 ]; then
        echo -e "${RED}Download failed.${NC}"
        echo "Please check your network and try again."
        exit -1
    else
        # chmod +x $RPI3_GPIOVIRTBUF_FILE_NAME
        source ./camera_i2c>/dev/null 2>&1
    fi
}

grepcmd() {
    type $1 >/dev/null 2>&1 || {
        echo >&2 "Start install $1."
        return 1
    }
}

judgeI2c() {
    for element in ${array[@]}; do
        if [ "$1" = "$element" ]; then
            return 0
        fi
    done
    return 1
}

judgeSenorId() {
    if [ "$1" = "0c" ]; then
        i2ctransfer -y 10 w2@0x0c 0x01 0x03 r4
    elif [ "$1" = "1a" ]; then
        i2ctransfer -y 10 w2@0x1a 0x00 0x16 r2
    fi
}

camera() {
    while read lines; do
        for line in $lines; do
            case "$line" in
            [0-9a-zA-z][0-9a-zA-Z])
                array[arr_subscript]=$line
                let arr_subscript++
                ;;
            esac
        done
    done <$1

    judgeI2c 1a
    if [ $? -eq 0 ]; then
        SenorId=$(judgeSenorId 1a 2>&1)
        if [ "$SenorId" = "0x05 0x19" ]; then
            InstallName="imx519_kernel_driver_low_speed"
            OpenCameraName=imx519
            echo "Recognize that your camera is IMX519."
        elif [ "$SenorId" = "0x06 0x82" ]; then
            InstallName="64mp_pi_hawk_eye_kernel_driver"
            OpenCameraName=arducam_64mp
            echo "Recognize that your camera is 64MP."
        fi

    fi

    if [ -z "$InstallName" ]; then

        SenorId=$(judgeSenorId 0c 2>&1)
        
        judgeI2c 0c
        if [ $? -eq 0 ]; then
            if [ "$SenorId" = "0x00 0x00 0x00 0x30" ]; then
                InstallName="kernel_driver"
                OpenCameraName=arducam
                echo "Recognize that your camera is Pirvarty"
            fi
        fi
    fi

    if [ -z "$InstallName" ]; then
        echo "Your camera does not need to install drivers."
        exit -1
    fi
}


openCamera() {
    if [ -n "$OpenCameraName" ]; then
        sudo dtoverlay $OpenCameraName>/dev/null 2>&1
    fi
}

autoDetect() {
    initAutodetect
    configCheck
    installFile
    i2cdetect -y 10 > i2c.txt
    camera i2c.txt
    # openCamera
    package=${InstallName}
}

autoDetect
