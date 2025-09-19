#!/usr/bin/env python3
"""
Complete workflow script for TinyPay payment process.
This script demonstrates the full process from initial data to Move contract parameters.
"""
import hashlib
import json
from hex_to_ascii_bytes import hex_to_ascii_bytes

def complete_payment_workflow(initial_data: str, iterations: int = 1000):
    """
    Complete workflow for preparing payment data for Move contract.
    
    Args:
        initial_data: Initial string data
        iterations: Number of SHA256 iterations
    
    Returns:
        dict: Contains all necessary data for Move contract call
    """
    print(f"=== TinyPay Payment Workflow ===")
    print(f"Initial data: {initial_data}")
    print(f"Iterations: {iterations}")
    print()
    
    # Step 1: Perform iterative hashing
    s = initial_data.encode()
    iteration_results = []
    
    for i in range(iterations):
        h = hashlib.sha256(s).hexdigest()
        iteration_results.append(h)
        if i < 3 or i >= iterations - 3:  # Show first 3 and last 3
            print(f"Iteration {i+1}: {h}")
        elif i == 3:
            print("...")
        s = h.encode("ascii")
    
    print()
    
    # Step 2: Prepare Move contract parameters
    if iterations > 1:
        otp_hex = iteration_results[-2]  # Second to last iteration
        tail_hex = iteration_results[-1]  # Final iteration
    else:
        otp_hex = initial_data
        tail_hex = iteration_results[0]
    
    # Step 3: Convert to ASCII bytes
    otp_ascii_bytes = hex_to_ascii_bytes(otp_hex)
    tail_ascii_bytes = hex_to_ascii_bytes(tail_hex)
    
    # Step 4: Prepare results
    result = {
        "otp_hex": otp_hex,
        "tail_hex": tail_hex,
        "otp_ascii_bytes": otp_ascii_bytes,
        "tail_ascii_bytes": tail_ascii_bytes,
        "otp_json": json.dumps(otp_ascii_bytes),
        "tail_json": json.dumps(tail_ascii_bytes),
        "aptos_otp_format": f"u8:[{','.join(map(str, otp_ascii_bytes))}]",
        "aptos_tail_format": f"u8:[{','.join(map(str, tail_ascii_bytes))}]"
    }
    
    # Step 5: Verification
    # The verification should hash the hex string as ASCII bytes, not the raw bytes
    verification_hash = hashlib.sha256(otp_hex.encode('ascii')).hexdigest()
    verification_ok = verification_hash == tail_hex
    
    print("=== Results ===")
    print(f"otp (hex): {otp_hex}")
    print(f"tail (hex): {tail_hex}")
    print()
    print(f"otp (ASCII bytes): {otp_ascii_bytes}")
    print(f"tail (ASCII bytes): {tail_ascii_bytes}")
    print()
    print("=== Aptos CLI Format ===")
    print(f"otp parameter: {result['aptos_otp_format']}")
    print(f"tail parameter: {result['aptos_tail_format']}")
    print()
    print("=== Verification ===")
    print(f"otp_hex as ASCII: {otp_hex.encode('ascii')}")
    print(f"SHA256(otp_hex as ASCII): {verification_hash}")
    print(f"Expected (tail_hex): {tail_hex}")
    print(f"Verification: {'✓ PASS' if verification_ok else '✗ FAIL'}")
    
    result["verification_ok"] = verification_ok
    return result

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Complete TinyPay payment workflow")
    parser.add_argument("data", help="Initial data string")
    parser.add_argument("-n", "--iterations", type=int, default=1000, 
                       help="Number of iterations (default: 1000)")
    parser.add_argument("--json-output", action="store_true",
                       help="Output results as JSON")
    
    args = parser.parse_args()
    
    result = complete_payment_workflow(args.data, args.iterations)
    
    if args.json_output:
        print("\n=== JSON Output ===")
        print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
