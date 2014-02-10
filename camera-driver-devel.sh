#!/usr/bin/env bash

set -e

KERNEL_SOURCE=
DEVICE_NAME=
I2C_RW_WIDTH=
DEVICE_NAME_UPPER=
TARGET_DRIVER=
RESOLUTIONS=
MIN_FRAME_RATE=
MAX_FRAME_RATE=
declare -a FRAME_RATE_ARRAY

function usage()
{
    echo "Usage: $0 <kernel_source_top>"
}

function check_arg()
{
    if [ $# -lt 1 ]; then
        usage
        exit 1
    fi

    local src=${1}
    if [ ! -d ${src} ]; then
        echo "Error: ${src} is not directory, you must give kernel_source_top directory name"
        exit 2
    fi

    src=${src%\/}
    if [ ! -e ${src}/drivers/media/video/Kconfig ]; then
        echo "Error: Invalid kernel source"
        exit 3
    fi

    KERNEL_SOURCE=${src}
}

function choice {
    CHOICE=''
    local prompt="$*"
    local answer
    read -p "$prompt" answer
    case "$answer" in
        [yY1] ) CHOICE='y';;
        [nN0] ) CHOICE='n';;
        *     ) CHOICE="$answer";;
    esac
} # end of function choic

function query_device_name()
{
    local name=""
    until [ ${#name} -gt 0 ]; do
        read -p "===> What's your camera sensor device name? " name
    done
    DEVICE_NAME=${name}
}

function query_i2c_read_write_width()
{
    local width=
    echo "===> Select your sensor i2c register r/w width "
    select width in 1byte 2byte; do
        if [ -n "${width}" ]; then
            I2C_RW_WIDTH=${width:0:1}
            break
        else
            echo "You must select width!!!"
        fi
    done
}

function query_resolution()
{
    local resolutions=""
    local answer=""
    until [ ${#resolutions} -gt 0 ]; do
        read -p "===> Supported Resolutions? (ex> 320x240,640x480,1024x768,2048x1536) " resolutions
        choice "${resolutions} is right?[Y/n] "
        if [ ${CHOICE} == "y" ]; then
            RESOLUTIONS=${resolutions}
            break
        else
            resolutions=""
        fi
    done
}

function query_framerate()
{
    local min=""
    local answer=""
    until [ ${#min} -gt 0 ]; do
        read -p "===> Minimum Framerate for ${1}? (ex> 15)" min
        choice "${min} is right?[Y/n] "
        if [ ${CHOICE} == "y" ]; then
            break
        else
            min=""
        fi
    done

    local max=""
    answer=""
    until [ ${#max} -gt 0 ]; do
        read -p "===> Maximum Framerate? (ex> 30)" max
        choice "${max} is right?[Y/n] "
        if [ ${CHOICE} == "y" ]; then
            break
        else
            max=""
        fi
    done
    echo "${1},${min},${max}"
}

function to_upper()
{
     if [ -z ${1} ]; then
         echo "Usage: to_upper string"
         exit
     fi

     local upper=$(echo ${1} | tr '[:lower:]' '[:upper:]')
     echo ${upper}
}

function make_resolution_table()
{
    local resolutions=$(echo ${RESOLUTIONS} | tr ',' ' ')
    local i=
    for i in ${resolutions}; do
        local width=${i%x[0-9]*}
        local height=${i#[0-9]*x}
        echo "
static struct regval resolution_${width}_${height}[] = {
    ENDMARKER,
};
"
    done

    echo "
static struct camera_sensor_resolution sensor_resolution_table[] = {"
    for i in ${resolutions}; do
        local width=${i%x[0-9]*}
        local height=${i#[0-9]*x}
        echo "
    {
        .width  = ${width},
        .height = ${height},
        .regval = resolution_${width}_${height},
    },
"
    done
    echo "};"
}

function make_driver()
{
    echo "make driver: ${TARGET_DRIVER}"

    local regval_list_value=""
    local write_array_func=""
    local ctrls_num=8
    local resolution_table=""

    if [ ${I2C_RW_WIDTH} == "1" ]; then
        regval_list_value="unsigned char value"
        write_array_func="
static _write_array(struct i2c_client *client, const struct regval *entrys)
{
    int ret;
    const struct regval *pentry = entrys;
    while (pentry->addr != 0xff) {
        ret = i2c_smbus_write_byte_data(client, pentry->addr, pentry->value);
        if (ret < 0) {
            printk("%s: failed\n", __func__);
            return ret;
        }
        pentry++;
    }
    return 0;
}"
    else
        regval_list_value="unsigned short value"
        write_array_func="
static int _write_twobyte(struct i2c_client *client, const struct regval *entry)
{
    int ret = 0;
    unsigned char buf[4];
    struct i2c_msg msg = {client->addr, 0, 4, buf};

    buf[0] = entry->addr >> 8;
    buf[1] = entry->addr;
    buf[2] = entry->value >> 8;
    buf[3] = entry->value;

    ret = i2c_transfer(client->adapter, &msg, 1);
    if (ret != 1) {
        return -1;
    }
    return 0;
}

static _write_array(struct i2c_client *client, const struct regval *entrys)
{
    int ret;
    const struct regval *pentry = entrys;
    while (pentry->reg_num != 0xff) {
        ret = _write_twobyte(client, pentry);
        if (ret < 0) {
            printk("%s: failed\n", __func__);
            return ret;
        }
        pentry++;
    }
    return 0;
}"
    fi

    resolution_table=$(make_resolution_table)

    echo "
#include <linux/module.h>
#include <linux/i2c.h>
#include <linux/slab.h>
#include <linux/videodev2.h>
#include <linux/v4l2-subdev.h>
#include <media/v4l2-device.h>
#include <media/v4l2-subdev.h>
#include <media/v4l2-ctrls.h>

#define MODULE_NAME \"${DEVICE_NAME_UPPER}\"

struct regval {
    unsigned short addr;
    ${regval_list_value};
}

#define ENDMARKER { 0xff, 0xff }

struct camera_sensor_resolution {
    int width;
    int height;
    struct regval *regval;
};

struct ${DEVICE_NAME}_priv {
    struct v4l2_subdev        subdev;
    struct media_pad          pad;
    struct v4l2_ctrl_handler  hdl;
    bool                      initialized;

    struct v4l2_ctrl *ctrl_focus_auto;
    struct v4l2_ctrl *ctrl_colorfx;
    struct v4l2_ctrl *ctrl_scene_mode;
    struct v4l2_ctrl *ctrl_power_line_frequency;
    struct v4l2_ctrl *ctrl_white_balance_preset;
    struct v4l2_ctrl *ctrl_exposure;
    struct v4l2_ctrl *ctrl_flash_strobe;
    struct v4l2_ctrl *ctrl_flash_strobe_stop;
    struct v4l2_ctrl *ctrl_running_mode;

    struct camera_sensor_resolution *cur_resolution;
};

${resolution_table}

static inline struct ${DEVICE_NAME}_priv *to_priv(struct v4l2_subdev *subdev)
{
    return container_of(subdev, struct ${DEVICE_NAME}_priv, subdev);
}

static inline struct v4l2_subdev *ctrl_to_sd(struct v4l2_ctrl *ctrl)
{
    return &container_of(ctrl->handler, struct ${DEVICE_NAME}_priv, hdl)->subdev;
}

${write_array_func}

#define DECLARE_CTRL_VAR() \
    struct i2c_client *client = v4l2_get_subdevdata(sd); \
    struct ${DEVICE_NAME}_priv *priv = to_priv(sd)

/**
 * autofocus regs
 */
static struct regval _focus_auto_on_reglist = {
    ENDMARKER,
};

/**
 * colorfx regs
 */
static struct regval _focus_auto_off_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_none_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_bw_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_sepia_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_negative_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_emboss_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_sketch_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_sky_blue_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_grass_green_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_skin_whiten_reglist = {
    ENDMARKER,
};

static struct regval _colorfx_vivid_reglist = {
    ENDMARKER,
};

/**
 * scene_mode regs
 */
static struct regval _scene_mode_auto_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_action_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_portrait_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_landscape_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_night_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_night_portrait_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_theatre_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_beach_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_snow_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_sunset_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_steadyphoto_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_fireworks_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_sports_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_party_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_candlelight_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_barcode_reglist = {
    ENDMARKER,
};

static struct regval _scene_mode_hdr_reglist = {
    ENDMARKER,
};

/**
 * power line frequency regs
 */
static struct regval _power_line_frequency_disabled_reglist = {
    ENDMARKER,
};

static struct regval _power_line_frequency_50hz_reglist = {
    ENDMARKER,
};

static struct regval _power_line_frequency_60hz_reglist = {
    ENDMARKER,
};

static struct regval _power_line_frequency_auto_reglist = {
    ENDMARKER,
};

/**
 * white balance preset regs
 */
static struct regval _white_balance_auto_reglist = {
    ENDMARKER,
};

static struct regval _white_balance_sunny_reglist = {
    ENDMARKER,
};

static struct regval _white_balance_cloudy_reglist = {
    ENDMARKER,
};

static struct regval _white_balance_tungsten_reglist = {
    ENDMARKER,
};

static struct regval _white_balance_fluorescent_reglist = {
    ENDMARKER,
};

/**
 * exposure regs
 */
static struct regval _exposure_minus_4_reglist = {
    ENDMARKER,
};

static struct regval _exposure_minus_3_reglist = {
    ENDMARKER,
};

static struct regval _exposure_minus_2_reglist = {
    ENDMARKER,
};

static struct regval _exposure_minus_1_reglist = {
    ENDMARKER,
};

static struct regval _exposure_0_reglist = {
    ENDMARKER,
};

static struct regval _exposure_plus_1_reglist = {
    ENDMARKER,
};

static struct regval _exposure_plus_2_reglist = {
    ENDMARKER,
};

static struct regval _exposure_plus_3_reglist = {
    ENDMARKER,
};

static struct regval _exposure_plus_4_reglist = {
    ENDMARKER,
};

/**
 * flash regs
 */
struct regval _flash_on_reglist = {
    ENDMARKER,
};

struct regval _flash_off_reglist = {
    ENDMARKER,
};

/**
 * running mode regs
 */
struct regval _running_mode_preview_reglist = {
    ENDMARKER,
};

struct regval _running_mode_capture_reglist = {
    ENDMARKER,
};

/**
 * ctrl functions
 */
static int ctrl_focus_auto(struct v4l2_subdev *sd, struct v4l2_ctrl *ctrl)
{
    DECLARE_CTRL_VAR();

    if (ctrl->val > 0)
        return _write_array(client, _focus_auto_on_reglist);
    else
        return _write_array(client, _focus_auto_off_reglist);
}

static int ctrl_colorfx(struct v4l2_subdev *sd, struct v4l2_ctrl *ctrl)
{
    DECLARE_CTRL_VAR();

    switch (ctrl->val) {
    case V4L2_COLORFX_NONE:
        return _write_array(client, _colorfx_none_reglist);

    case V4L2_COLORFX_BW:
        return _write_array(client, _colorfx_bw_reglist);

    case V4L2_COLORFX_SEPIA:
        return _write_array(client, _colorfx_sepia_reglist);

    case V4L2_COLORFX_NEGATIVE:
        return _write_array(client, _colorfx_negative_reglist);

    case V4L2_COLORFX_EMBOSS:
        return _write_array(client, _colorfx_emboss_reglist);

    case V4L2_COLORFX_SKETCH:
        return _write_array(client, _colorfx_sketch_reglist);

    case V4L2_COLORFX_GRASS_GREEN:
        return _write_array(client, _colorfx_grass_green_reglist);

    case V4L2_COLORFX_SKIN_WHITEN:
        return _write_array(client, _colorfx_skin_whiten_reglist);

    case V4L2_COLORFX_VIVID:
        return _write_array(client, _colorfx_vivid_reglist);

    default:
        printk(KERN_ERR \"%s: invalid val(ctrl->val)\\n\", __func__, ctrl->val);
        return -EINVAL;
    }
}

static int ctrl_scene_mode(struct v4l2_subdev *sd, struct v4l2_ctrl *ctrl)
{
    DECLARE_CTRL_VAR();

    switch (ctrl->val) {
    case v4l2_scene_mode_auto:
        return _write_array(client, _scene_mode_auto_reglist);

    case v4l2_scene_mode_action:
        return _write_array(client, _scene_mode_action_reglist);

    case v4l2_scene_mode_portrait:
        return _write_array(client, _scene_mode_portrait_reglist);

    case v4l2_scene_mode_landscape:
        return _write_array(client, _scene_mode_landscape_reglist);

    case v4l2_scene_mode_night:
        return _write_array(client, _scene_mode_night_reglist);

    case v4l2_scene_mode_night_portrait:
        return _write_array(client, _scene_mode_night_portrait_reglist);

    case v4l2_scene_mode_theatre:
        return _write_array(client, _scene_mode_theatre_reglist);

    case v4l2_scene_mode_beach:
        return _write_array(client, _scene_mode_beach_reglist);

    case v4l2_scene_mode_snow:
        return _write_array(client, _scene_mode_snow_reglist);

    case v4l2_scene_mode_sunset:
        return _write_array(client, _scene_mode_sunset_reglist);

    case v4l2_scene_mode_steadyphoto:
        return _write_array(client, _scene_mode_steadyphoto_reglist);

    case v4l2_scene_mode_fireworks:
        return _write_array(client, _scene_mode_fireworks_reglist);

    case v4l2_scene_mode_sports:
        return _write_array(client, _scene_mode_sports_reglist);

    case v4l2_scene_mode_party:
        return _write_array(client, _scene_mode_party_reglist);

    case v4l2_scene_mode_candlelight:
        return _write_array(client, _scene_mode_candlelight_reglist);

    case v4l2_scene_mode_barcode:
        return _write_array(client, _scene_mode_barcode_reglist);

    case v4l2_scene_mode_hdr:
        return _write_array(client, _scene_mode_hdr_reglist);

    default:
        printk(KERN_ERR \"%s: invalid val(0x%x)\\n\".__func__, ctrl->val);
        return -EINVAL;
    }
}

static int ctrl_power_line_frequency(struct v4l2_subdev *sd, struct v4l2_ctrl *ctrl)
{
    DECLARE_CTRL_VAR();

    switch (ctrl->val) {
    case V4L2_CID_POWER_LINE_FREQUENCY_DISABLED:
        return _write_array(client, _power_line_frequency_disabled_reglist);

    case V4L2_CID_POWER_LINE_FREQUENCY_50HZ:
        return _write_array(client, _power_line_frequency_50hz_reglist);

    case V4L2_CID_POWER_LINE_FREQUENCY_60Hz:
        return _write_array(client, _power_line_frequency_60hz_reglist);

    case V4L2_CID_POWER_LINE_FREQUENCY_AUTO:
        return _write_array(client, _power_line_frequency_auto_reglist);

    default:
        printk(KERN_ERR \"%s: invalid value(0x%x)\\n\", __func__, ctrl->val);
        return -EINAL;
    }
}

static int ctrl_white_balance_preset(struct v4l2_subdev *sd, struct v4l2_ctrl *ctrl)
{
    DECLARE_CTRL_VAR();

    switch (ctrl->val) {
    case V4L2_WHITE_BALANCE_AUTO:
        return _write_array(client, _white_balance_auto_reglist);

    case V4L2_WHITE_BALANCE_SUNNY:
        return _write_array(client, _white_balance_sunny_reglist);

    case V4L2_WHITE_BALANCE_CLOUDY:
        return _write_array(client, _white_balance_cloudy_reglist);

    case V4L2_WHITE_BALANCE_TUNGSTEN:
        return _write_array(client, _white_balance_fluorescent_reglist);

    case V4L2_WHITE_BALANCE_FLUORESCENT:
        return _write_array(client, _white_balance_fluorescent_reglist);

    default:
        printk(KERN_ERR \"%s: invalid value(0x%x)\\n\", __func__, ctrl->val);
        return -EINVAL;
    }
}

static int ctrl_exposure(struct v4l2_subdev *sd, struct v4l2_ctrl *ctrl)
{
    DECLARE_CTRL_VAR();

    switch (ctrl->val) {
    case V4L2_EXPOSURE_MINUS_4:
        return _write_array(client, _exposure_minus_4_reglist);

    case V4L2_EXPOSURE_MINUS_3:
        return _write_array(client, _exposure_minus_3_reglist);

    case V4L2_EXPOSURE_MINUS_2:
        return _write_array(client, _exposure_minus_2_reglist);

    case V4L2_EXPOSURE_MINUS_1:
        return _write_array(client, _exposure_minus_1_reglist);

    case V4L2_EXPOSURE_0:
        return _write_array(client, _exposure_0_reglist);

    case V4L2_EXPOSURE_PLUS_1:
        return _write_array(client, _exposure_plus_1_reglist);

    case V4L2_EXPOSURE_PLUS_2:
        return _write_array(client, _exposure_plus_2_reglist);

    case V4L2_EXPOSURE_PLUS_3:
        return _write_array(client, _exposure_plus_3_reglist);

    case V4L2_EXPOSURE_PLUS_4:
        return _write_array(client, _exposure_plus_4_reglist);

    default:
        printk(KERN_ERR \"%s: invalid value(0x%x)\\n\", __func__, ctrl->val);
        return -EINVAL;
    }
}

static int ctrl_flash_strobe(struct v4l2_subdev *sd, struct v4l2_ctrl *ctrl)
{
    DECLARE_CTRL_VAR();
    return _write_array(client, _flash_on_reglist);
}

static int ctrl_flash_strobe_stop(struct v4l2_subdev *sd, struct v4l2_ctrl *ctrl)
{
    DECLARE_CTRL_VAR();
    return _write_array(client, _flash_off_reglist);
}

static int ctrl_running_mode(struct v4l2_subdev *sd, struct v4l2_ctrl *ctrl)
{
    DECLARE_CTRL_VAR();

    switch (ctrl->val) {
    case V4L2_RUNNING_PREVIEW:
        return _write_array(client, _running_mode_preview_reglist);

    case V4L2_RUNNING_CAPTURE:
        return _write_array(cliet, _running_mode_capture_reglist);

    default:
        printk(KERN_ERR \"%s: invalid value(0x%x)\\n\", __func__, ctrl->val);
        return -EINVAL;
    }
}

static int ${DEVICE_NAME}_s_ctrl(struct v4l2_ctrl *ctrl)
{
    struct v4l2_subdev *sd = ctrl_to_sd(ctrl);

    switch (ctrl->id) {
    case V4L2_CID_FOCUS_AUTO:
        return ctrl_focus_auto(sd, ctrl);

    case V4L2_CID_COLORFX:
        return ctrl_colorfx(sd, ctrl);

    case V4L2_CID_SCENE_MODE:
        return ctrl_scene_mode(sd, ctrl);

    case V4L2_CID_POWER_LINE_FREQUENCY:
        return ctrl_power_line_frequency(sd, ctrl);

    case V4L2_CID_WHITE_BALANCE_PRESET:
        return ctrl_white_balance_preset(sd, ctrl);

    case V4L2_CID_EXPOSURE:
        return ctrl_exposure(sd, ctrl);

    case V4L2_FLASH_STROBE:
        return ctrl_flash_strobe(sd, ctrl);

    case V4L2_FLASH_STROBE_STOP:
        return ctrl_flash_strobe_stop(sd, ctrl);

    case V4L2_CID_RUNNING_MODE:
        return ctrl_running_mode(sd, ctrl);

    default:
        printk(KERN_ERR \"%s: invalid control id(0x%x)\\n\", __func__, ctrl->id);
        return -EINVAL;
    }
}

static const struct v4l2_ctrl_ops ${DEVICE_NAME}_ctrl_ops = {
    .s_ctrl = ${DEVICE_NAME}_s_ctrl,
};

static int _initialize_ctrls(struct ${DEVICE_NAME}_priv *priv)
{
    v4l2_ctrl_handler_init(&priv->hdl, ${ctrls_num});

    priv->ctrl_focus_auto = v4l2_ctrl_new_std(&priv->hdl, &${DEVICE_NAME}_ctrl_ops,
                                V4L2_CID_FOCUS_AUTO, 0, 1, 1, 0);
    if (!priv->ctrl_focus_auto) {
        printk(KERN_ERR \"%s: failed to create ctrl_focus_auto\\n\", __func__);
        return -ENOENT;
    }

    priv->ctrl_colorfx = v4l2_ctrl_new_std(&priv->hdl, &${DEVICE_NAME}_ctrl_ops,
                                V4L2_CID_COLORFX, 0, V4L2_COLORFX_MAX - 1, 1, 0);
    if (!priv->ctrl_colorfx) {
        printk(KERN_ERR \"%s: failed to create ctrl_colorfx\\n\", __func__);
        return -ENOENT;
    }

    priv->ctrl_scene_mode = v4l2_ctrl_new_std(&priv->hdl, &${DEVICE_NAME}_ctrl_ops,
                                V4L2_CID_SCENE_MODE, 0, v4l2_scene_mode_max - 1, 1, 0);
    if (!priv->ctrl_scene_mode) {
        printk(KERN_ERR \"%s: failed to create ctrl_scene_mode\\n\", __func__);
        return -ENOENT;
    }

    priv->ctrl_power_line_frequency = v4l2_ctrl_new_std(&priv->hdl, &${DEVICE_NAME}_ctrl_ops,
                                V4L2_CID_POWER_LINE_FREQUENCY, 0, V4L2_CID_POWER_LINE_FREQUENCY_MAX - 1, 1, 0);
    if (!priv->ctrl_power_line_frequency) {
        printk(KERN_ERR \"%s: failed to create ctrl_power_line_frequency\\n\", __func__);
        return -ENOENT;
    }

    priv->ctrl_white_balance_preset = v4l2_ctrl_new_std(&priv->hdl, &${DEVICE_NAME}_ctrl_ops,
                                V4L2_CID_WHITE_BALANCE_PRESET, 0, V4L2_CID_WHITE_BALANCE_MAX - 1, 1, 0);
    if (!priv->ctrl_white_balance_preset) {
        printk(KERN_ERR \"%s: failed to create ctrl_white_balance_preset\\n\", __func__);
        return -ENOENT;
    }

    priv->ctrl_exposure = v4l2_ctrl_new_std(&priv->hdl, &${DEVICE_NAME}_ctrl_ops,
                                V4L2_CID_EXPOSURE, 0, V4L2_CID_EXPOSURE_MAX - 1, 1, 0);
    if (!priv->ctrl_exposure) {
        printk(KERN_ERR \"%s: failed to create ctrl_exposure\\n\", __func__);
        return -ENOENT;
    }

    priv->ctrl_flash_strobe = v4l2_ctrl_new_std(&priv->hdl, &${DEVICE_NAME}_ctrl_ops,
                                V4L2_FLASH_STROBE, 0, 0, 0, 0);
    if (!priv->ctrl_flash_strobe) {
        printk(KERN_ERR \"%s: failed to create ctrl_flash_strobe\\n\", __func__);
        return -ENOENT;
    }

    priv->ctrl_flash_strobe_stop = v4l2_ctrl_new_std(&priv->hdl, &${DEVICE_NAME}_ctrl_ops,
                                V4L2_FLASH_STROBE_STOP, 0, 0, 0, 0);
    if (!priv->ctrl_flash_strobe_stop) {
        printk(KERN_ERR \"%s: failed to create ctrl_flash_strobe_stop\\n\", __func__);
        return -ENOENT;
    }

    priv->ctrl_running_mode = v4l2_ctrl_new_std(&priv->hdl, &${DEVICE_NAME}_ctrl_ops,
                                V4L2_CID_RUNNING_MODE, 0, 1, 1, 0);
    if (!priv->ctrl_running_mode) {
        printk(KERN_ERR \"%s: failed to create ctrl_running_mode\\n\", __func__);
        return -ENOENT;
    }

    priv->subdev.ctrl_handler = &priv->hdl;
    if (priv->hdl.error) {
        printk(KERN_ERR \"%s: ctrl handler error(%d)\\n\", __func__, priv->hdl.error);
        v4l2_ctrl_handler_free(&priv->hdl);
        return -EINVAL;
    }

    return 0;
}

static int ${DEVICE_NAME}_s_power(struct v4l2_subdev *sd, int on)
{
    if (!on) {
        struct ${DEVICE_NAME}_priv *priv = to_priv(sd);
        priv->initialized = false;
    }
    return 0;
}

static const struct v4l2_subdev_core_ops ${DEVICE_NAME}_subdev_core_ops = {
    .s_power = ${DEVICE_NAME}_s_power,
    .s_ctrl  = v4l2_subdev_s_ctrl,
};

static int ${DEVICE_NAME}_enum_framesizes(struct v4l2_subdev *sd, struct v4l2_frmsizeenum *fsize)
{
    struct i2c_client *client = v4l2_get_subdevdata(sd);

    if (fsize->index >= ARRAY_SIZE(sensor_resolution_table)) {
        printk(KERN_ERR \"%s: index(%d) is out of range %d\\n\", fsize->index, ARRAY_SIZE(sensor_resolution_table));
        return -EINVAL;
    }

    fsize->type = V4L2_FRMSIZE_TYPE_DESCRETE;
    fsize->discrete.width  = sensor_resolution_table[fsize->index].width;
    fsize->discrete.height = sensor_resolution_table[fsize->index].height;

    return 0;
}
"
}

check_arg $@
echo "KERNEL_SOURCE: ${KERNEL_SOURCE}"

query_device_name
echo "DEVICE_NAME: ${DEVICE_NAME}"

query_i2c_read_write_width
echo "I2C_RW_WIDTH: ${I2C_RW_WIDTH}"

query_resolution
echo "RESOLUTIONS: ${RESOLUTIONS}"

frame_rate_index=0
frame_rate=""
for i in ${RESOLUTIONS//,/ }; do
    #FRAME_RATE_ARRAY[${frame_rate_index}]=$(query_framerate ${i})
    #frame_rate=$(query_framerate ${i})
    #echo "index ${frame_rate_index}'s framerate: ${frame_rate}"
    #let frame_rate_index++
    echo $i
done
echo "FRAME_RATE_ARRAY: ${FRAME_RATE_ARRAY}"

DEVICE_NAME_UPPER=$(to_upper ${DEVICE_NAME})
echo "DEVICE_NAME_UPPER: ${DEVICE_NAME_UPPER}"

TARGET_DRIVER=${KERNEL_SOURCE}/drivers/media/video/${DEVICE_NAME}.c
echo "TARGET_DRIVER: ${TARGET_DRIVER}"

#make_resolution_table

