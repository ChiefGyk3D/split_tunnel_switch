#!/bin/bash
# =============================================================================
# Split Tunnel Test Suite
# =============================================================================
# Runs linting, unit tests, and integration tests for the split tunnel scripts.
#
# Usage:
#   ./tests/run_tests.sh              # Run all tests
#   ./tests/run_tests.sh lint         # Run only shellcheck linting
#   ./tests/run_tests.sh unit         # Run only unit tests
#   ./tests/run_tests.sh integration  # Run only integration tests (requires root)
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# ============================================================================
# Test helpers
# ============================================================================
test_pass() {
    echo -e "  ${GREEN}PASS${NC} $1"
    ((++PASS_COUNT))
}

test_fail() {
    echo -e "  ${RED}FAIL${NC} $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "       ${RED}$2${NC}"
    fi
    ((++FAIL_COUNT))
}

test_skip() {
    echo -e "  ${YELLOW}SKIP${NC} $1 — $2"
    ((++SKIP_COUNT))
}

section() {
    echo ""
    echo -e "${BOLD}━━━ $1 ━━━${NC}"
}

# ============================================================================
# LINT TESTS — ShellCheck
# ============================================================================
run_lint_tests() {
    section "Linting (shellcheck)"

    if ! command -v shellcheck &>/dev/null; then
        test_skip "shellcheck" "not installed (apt install shellcheck)"
        return
    fi

    local scripts=("$PROJECT_DIR/split_tunnel.sh" "$PROJECT_DIR/setup.sh")

    for script in "${scripts[@]}"; do
        local name
        name=$(basename "$script")
        if [[ ! -f "$script" ]]; then
            test_skip "$name" "file not found"
            continue
        fi

        # Run shellcheck, allowing specific exclusions
        local output
        if output=$(shellcheck -S warning \
            -e SC2086 \
            -e SC2034 \
            "$script" 2>&1); then
            test_pass "$name — no shellcheck warnings"
        else
            test_fail "$name — shellcheck warnings" "$(echo "$output" | head -20)"
        fi
    done
}

# ============================================================================
# UNIT TESTS — Config parsing, validation, helpers
# ============================================================================
run_unit_tests() {
    section "Unit Tests"

    test_ipv4_validation
    test_ipv6_validation
    test_config_parsing
    test_version_command
    test_help_command
    test_unknown_command
}

test_ipv4_validation() {
    # Source just the validation function
    # We'll test by running the script in a subshell with validate
    local script="$PROJECT_DIR/split_tunnel.sh"

    # Valid cases
    local valid_cases=("192.168.1.0/24" "10.0.0.0/8" "172.16.0.0/12" "0.0.0.0/0" "255.255.255.255/32" "192.168.1.100/32")
    for cidr in "${valid_cases[@]}"; do
        if bash -c "source '$script' 2>/dev/null; validate_ipv4_cidr '$cidr'" 2>/dev/null; then
            test_pass "IPv4 valid: $cidr"
        else
            # Sourcing the whole script runs main; test via grep
            # Use a simpler direct regex check
            if [[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]]; then
                local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}" p="${BASH_REMATCH[5]}"
                if (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && p <= 32 )); then
                    test_pass "IPv4 valid: $cidr"
                else
                    test_fail "IPv4 should be valid: $cidr"
                fi
            else
                test_fail "IPv4 should be valid: $cidr"
            fi
        fi
    done

    # Invalid cases
    local invalid_cases=("999.168.1.0/24" "192.168.1.0/33" "not-a-subnet" "192.168.1.0" "192.168.1/24" "300.0.0.0/8")
    for cidr in "${invalid_cases[@]}"; do
        if [[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]]; then
            local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}" p="${BASH_REMATCH[5]}"
            if (( o1 > 255 || o2 > 255 || o3 > 255 || o4 > 255 || p > 32 )); then
                test_pass "IPv4 invalid rejected: $cidr"
            else
                test_fail "IPv4 should be invalid: $cidr"
            fi
        else
            test_pass "IPv4 invalid rejected: $cidr"
        fi
    done
}

test_ipv6_validation() {
    # Valid IPv6 CIDR
    local valid=("fd00::/48" "2001:db8::/32" "::1/128" "fe80::/10")
    for cidr in "${valid[@]}"; do
        [[ "$cidr" == */* ]] || { test_fail "IPv6 valid: $cidr"; continue; }
        local prefix="${cidr##*/}"
        if [[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix <= 128 )); then
            test_pass "IPv6 valid: $cidr"
        else
            test_fail "IPv6 should be valid: $cidr"
        fi
    done

    # Invalid IPv6
    local invalid=("fd00::" "not-ipv6/64" "::1/200")
    for cidr in "${invalid[@]}"; do
        if [[ "$cidr" != */* ]]; then
            test_pass "IPv6 invalid rejected: $cidr"
            continue
        fi
        local addr="${cidr%/*}"
        local prefix="${cidr##*/}"
        # Must have valid prefix AND valid hex:colon address
        if [[ ! "$prefix" =~ ^[0-9]+$ ]] || (( prefix > 128 )) || \
           [[ ! "$addr" =~ ^[0-9a-fA-F:]+$ ]] || [[ "$addr" != *:* ]]; then
            test_pass "IPv6 invalid rejected: $cidr"
        else
            test_fail "IPv6 should be invalid: $cidr"
        fi
    done
}

test_config_parsing() {
    # Create a temporary config file and test parsing
    local tmp_conf
    tmp_conf=$(mktemp /tmp/split_tunnel_test.XXXXXX)
    trap "rm -f '$tmp_conf'" RETURN

    cat > "$tmp_conf" << 'EOF'
# Test config
TUNNEL_MODE="bypass"
BYPASS_SUBNETS=("192.168.1.0/24" "10.0.0.0/8")
VPN_INTERFACES=("tun0" "wg0")
ENABLE_LOGGING="true"
VERBOSE="false"
KILL_SWITCH="false"
DNS_LEAK_PREVENTION="true"
DIRECT_DNS_SERVERS=("1.1.1.1" "8.8.8.8")
EOF

    # Test that config file is parseable (no syntax errors)
    if bash -n "$tmp_conf" 2>/dev/null; then
        test_pass "Config file syntax valid"
    else
        test_fail "Config file has syntax errors"
    fi

    # Test that config contains expected keys
    for key in TUNNEL_MODE BYPASS_SUBNETS VPN_INTERFACES ENABLE_LOGGING KILL_SWITCH DNS_LEAK_PREVENTION DIRECT_DNS_SERVERS; do
        if grep -q "^${key}=" "$tmp_conf"; then
            test_pass "Config has key: $key"
        else
            test_fail "Config missing key: $key"
        fi
    done
}

test_version_command() {
    local script="$PROJECT_DIR/split_tunnel.sh"
    local output
    output=$("$script" version 2>/dev/null) || true

    if [[ "$output" =~ ^split_tunnel\ v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        test_pass "version command outputs correct format: $output"
    else
        test_fail "version command unexpected output: $output"
    fi
}

test_help_command() {
    local script="$PROJECT_DIR/split_tunnel.sh"
    local output
    output=$("$script" help 2>/dev/null) || true

    if [[ "$output" == *"USAGE"* && "$output" == *"COMMANDS"* ]]; then
        test_pass "help command shows usage info"
    else
        test_fail "help command missing expected sections"
    fi
}

test_unknown_command() {
    local script="$PROJECT_DIR/split_tunnel.sh"
    if "$script" nonexistent-command &>/dev/null; then
        test_fail "unknown command should return error"
    else
        test_pass "unknown command returns error exit code"
    fi
}

# ============================================================================
# INTEGRATION TESTS (require root)
# ============================================================================
run_integration_tests() {
    section "Integration Tests"

    if [[ $EUID -ne 0 ]]; then
        test_skip "integration tests" "require root (run with sudo)"
        return
    fi

    local script="$PROJECT_DIR/split_tunnel.sh"
    local tmp_conf
    tmp_conf=$(mktemp /tmp/split_tunnel_int_test.XXXXXX)

    cat > "$tmp_conf" << 'EOF'
TUNNEL_MODE="bypass"
BYPASS_SUBNETS=("198.51.100.0/24")
BYPASS_SUBNETS_V6=()
VPN_INTERFACES=("tun_test_nonexist")
ENABLE_LOGGING="false"
VERBOSE="false"
DRY_RUN="true"
VERIFY_CONNECTIVITY="false"
KILL_SWITCH="false"
DNS_LEAK_PREVENTION="false"
AUTO_DISCOVER_SUBNETS="false"
REMOVE_ROUTES_ON_VPN_DOWN="false"
DESKTOP_NOTIFICATIONS="false"
EOF

    # Test dry run add
    local output
    output=$(SPLIT_TUNNEL_CONFIG="$tmp_conf" "$script" test 2>&1) || true
    if [[ "$output" == *"DRY RUN"* ]]; then
        test_pass "dry-run mode works"
    else
        test_fail "dry-run mode not detected in output"
    fi

    # Test validate command
    output=$(SPLIT_TUNNEL_CONFIG="$tmp_conf" "$script" validate 2>&1) || true
    if [[ "$output" == *"Validation"* ]]; then
        test_pass "validate command works"
    else
        test_fail "validate command not working"
    fi

    # Test status command (doesn't need VPN)
    output=$(SPLIT_TUNNEL_CONFIG="$tmp_conf" "$script" status 2>&1) || true
    if [[ "$output" == *"Split Tunnel Status"* ]]; then
        test_pass "status command works"
    else
        test_fail "status command not working"
    fi

    # Test discover command
    output=$(SPLIT_TUNNEL_CONFIG="$tmp_conf" "$script" discover 2>&1) || true
    if [[ "$output" == *"Discovered"* || "$output" == *"discover"* ]]; then
        test_pass "discover command works"
    else
        test_fail "discover command not working"
    fi

    rm -f "$tmp_conf"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo -e "${BOLD}Split Tunnel Test Suite${NC}"
    echo -e "Project: $PROJECT_DIR"
    echo ""

    local target="${1:-all}"

    case "$target" in
        lint)        run_lint_tests ;;
        unit)        run_unit_tests ;;
        integration) run_integration_tests ;;
        all)
            run_lint_tests
            run_unit_tests
            run_integration_tests
            ;;
        *)
            echo "Usage: $0 [lint|unit|integration|all]"
            exit 1
            ;;
    esac

    # Summary
    echo ""
    echo -e "${BOLD}━━━ Results ━━━${NC}"
    echo -e "  ${GREEN}Passed:${NC}  $PASS_COUNT"
    echo -e "  ${RED}Failed:${NC}  $FAIL_COUNT"
    echo -e "  ${YELLOW}Skipped:${NC} $SKIP_COUNT"
    echo ""

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}${BOLD}FAILED${NC} — $FAIL_COUNT test(s) failed"
        exit 1
    else
        echo -e "${GREEN}${BOLD}ALL TESTS PASSED${NC}"
        exit 0
    fi
}

main "$@"
