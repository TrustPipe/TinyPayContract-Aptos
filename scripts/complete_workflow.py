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
        opt_hex = iteration_results[-2]  # Second to last iteration
        tail_hex = iteration_results[-1]  # Final iteration
    else:
        opt_hex = initial_data
        tail_hex = iteration_results[0]
    
    # Step 3: Convert to ASCII bytes
    opt_ascii_bytes = hex_to_ascii_bytes(opt_hex)
    tail_ascii_bytes = hex_to_ascii_bytes(tail_hex)
    
    # Step 4: Prepare results
    result = {
        "opt_hex": opt_hex,
        "tail_hex": tail_hex,
        "opt_ascii_bytes": opt_ascii_bytes,
        "tail_ascii_bytes": tail_ascii_bytes,
        "opt_json": json.dumps(opt_ascii_bytes),
        "tail_json": json.dumps(tail_ascii_bytes),
        "aptos_opt_format": f"u8:[{','.join(map(str, opt_ascii_bytes))}]",
        "aptos_tail_format": f"u8:[{','.join(map(str, tail_ascii_bytes))}]"
    }
    
    # Step 5: Verification
    # The verification should hash the hex string as ASCII bytes, not the raw bytes
    verification_hash = hashlib.sha256(opt_hex.encode('ascii')).hexdigest()
    verification_ok = verification_hash == tail_hex
    
    print("=== Results ===")
    print(f"opt (hex): {opt_hex}")
    print(f"tail (hex): {tail_hex}")
    print()
    print(f"opt (ASCII bytes): {opt_ascii_bytes}")
    print(f"tail (ASCII bytes): {tail_ascii_bytes}")
    print()
    print("=== Aptos CLI Format ===")
    print(f"opt parameter: {result['aptos_opt_format']}")
    print(f"tail parameter: {result['aptos_tail_format']}")
    print()
    print("=== Verification ===")
    print(f"opt_hex as ASCII: {opt_hex.encode('ascii')}")
    print(f"SHA256(opt_hex as ASCII): {verification_hash}")
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
