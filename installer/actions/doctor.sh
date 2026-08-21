#!/usr/bin/env bash
# =============================================================================
# SCROW — doctor
# =============================================================================
# Environment checks + validation, exit-code report.

action_doctor() {
    doctor_checks
    local rc=$?
    printf "\n"
    return "$rc"
}
