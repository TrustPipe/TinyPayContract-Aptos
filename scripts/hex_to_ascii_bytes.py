#!/usr/bin/env python3
"""
Utility functions for converting hex strings to ASCII bytes.
Used in TinyPay payment processing workflow.
"""

def hex_to_ascii_bytes(hex_string: str) -> list[int]:
    """
    Convert a hex string to a list of ASCII byte values.
    
    This function takes a hex string and converts each character
    to its ASCII byte value for use in Move contracts.
    
    Args:
        hex_string: Hex string to convert (without 0x prefix)
        
    Returns:
        List of integers representing ASCII byte values of the hex string characters
        
    Example:
        hex_to_ascii_bytes("adb6") -> [97, 100, 98, 54]
        which represents the ASCII values of 'a', 'd', 'b', '6'
    """
    # Remove 0x prefix if present
    if hex_string.startswith('0x'):
        hex_string = hex_string[2:]
    
    # Convert each character of the hex string to its ASCII byte value
    ascii_bytes = []
    for char in hex_string:
        ascii_value = ord(char)
        ascii_bytes.append(ascii_value)
    
    return ascii_bytes

def ascii_bytes_to_hex(ascii_bytes: list[int]) -> str:
    """
    Convert a list of ASCII byte values back to a hex string.
    
    Args:
        ascii_bytes: List of integers representing ASCII byte values
        
    Returns:
        Hex string representation
        
    Example:
        ascii_bytes_to_hex([72, 101, 108, 108, 111]) -> "48656c6c6f"
    """
    return ''.join(f'{byte:02x}' for byte in ascii_bytes)

def ascii_bytes_to_string(ascii_bytes: list[int]) -> str:
    """
    Convert a list of ASCII byte values to a readable string.
    
    Args:
        ascii_bytes: List of integers representing ASCII byte values
        
    Returns:
        ASCII string representation
        
    Example:
        ascii_bytes_to_string([72, 101, 108, 108, 111]) -> "Hello"
    """
    return ''.join(chr(byte) for byte in ascii_bytes)

def format_for_aptos_cli(ascii_bytes: list[int]) -> str:
    """
    Format ASCII bytes for use with Aptos CLI.
    
    Args:
        ascii_bytes: List of integers representing ASCII byte values
        
    Returns:
        Formatted string for Aptos CLI vector<u8> parameter
        
    Example:
        format_for_aptos_cli([72, 101, 108, 108, 111]) -> "vector<u8>:[72,101,108,108,111]"
    """
    return f"vector<u8>:[{','.join(map(str, ascii_bytes))}]"

def main():
    """
    Command line interface for hex to ASCII bytes conversion.
    """
    import argparse
    import json
    
    parser = argparse.ArgumentParser(description="Convert hex strings to ASCII bytes")
    parser.add_argument("hex_string", help="Hex string to convert")
    parser.add_argument("--format", choices=["list", "aptos", "string", "json"], 
                       default="list", help="Output format")
    parser.add_argument("--reverse", action="store_true", 
                       help="Treat input as comma-separated ASCII bytes and convert to hex")
    
    args = parser.parse_args()
    
    if args.reverse:
        # Convert ASCII bytes to hex
        try:
            ascii_bytes = [int(x.strip()) for x in args.hex_string.split(',')]
            hex_result = ascii_bytes_to_hex(ascii_bytes)
            string_result = ascii_bytes_to_string(ascii_bytes)
            print(f"ASCII bytes: {ascii_bytes}")
            print(f"Hex string: {hex_result}")
            print(f"String: {string_result}")
        except ValueError as e:
            print(f"Error: Invalid ASCII bytes format - {e}")
            return 1
    else:
        # Convert hex to ASCII bytes
        try:
            ascii_bytes = hex_to_ascii_bytes(args.hex_string)
            
            if args.format == "list":
                print(ascii_bytes)
            elif args.format == "aptos":
                print(format_for_aptos_cli(ascii_bytes))
            elif args.format == "string":
                print(ascii_bytes_to_string(ascii_bytes))
            elif args.format == "json":
                print(json.dumps(ascii_bytes))
                
        except ValueError as e:
            print(f"Error: Invalid hex string - {e}")
            return 1
    
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())