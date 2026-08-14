#!/bin/bash
on_surface=$1
surface_container=$2
primary_container=$3
tertiary=$4
secondary=$5
primary=$6
on_surface_last=$7

CAVA="$HOME/.config/cava/config"

sed -i "s/^foreground = .*/foreground = '${on_surface}'/" "$CAVA"
sed -i "s/^gradient_color_1 = .*/gradient_color_1 = '${surface_container}'/" "$CAVA"
sed -i "s/^gradient_color_2 = .*/gradient_color_2 = '${primary_container}'/" "$CAVA"
sed -i "s/^gradient_color_3 = .*/gradient_color_3 = '${tertiary}'/" "$CAVA"
sed -i "s/^gradient_color_4 = .*/gradient_color_4 = '${secondary}'/" "$CAVA"
sed -i "s/^gradient_color_5 = .*/gradient_color_5 = '${primary}'/" "$CAVA"
sed -i "s/^gradient_color_6 = .*/gradient_color_6 = '${on_surface_last}'/" "$CAVA"
