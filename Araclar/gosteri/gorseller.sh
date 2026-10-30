#!/bin/bash
# GitHub sayfası resimleri: üst şerit (koyu/açık), özellik görselleri, sosyal önizleme → docs/
# Önce ./yap.sh --derle. Çizim: Sources/FingerKit/UI/PromoImages.swift
set -euo pipefail
cd "$(dirname "$0")/../.."
build/FingerKit.app/Contents/MacOS/FingerKit --gorselleri-ciz docs/images -AppleLanguages "(en)" -AppleLocale en_US
ls -la docs/images
