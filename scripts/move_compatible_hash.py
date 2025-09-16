#!/usr/bin/env python3
"""
Move 兼容的哈希处理脚本
按照 Aptos Move 的方式处理数据：BCS序列化 + SHA256哈希
与 tinypay.move 中的 complete_payment 函数兼容
"""

import sys
import argparse
import hashlib
import json
from typing import Any, Union


def serialize_to_bcs_like(data: Any) -> bytes:
    """
    简化的 BCS 序列化实现
    这里实现一个基础版本，用于与 Move 代码兼容测试
    实际项目中应该使用官方的 BCS 库
    """
    if isinstance(data, bool):
        return b'\x01' if data else b'\x00'
    elif isinstance(data, int):
        if data < 0:
            raise ValueError("BCS does not support negative integers")
        # u64 编码为小端字节序
        return data.to_bytes(8, 'little')
    elif isinstance(data, str):
        # 字符串编码为长度前缀 + UTF-8 字节
        utf8_bytes = data.encode('utf-8')
        length = len(utf8_bytes)
        return length.to_bytes(8, 'little') + utf8_bytes
    elif isinstance(data, bytes):
        # 字节数组编码为长度前缀 + 字节内容
        length = len(data)
        return length.to_bytes(8, 'little') + data
    elif isinstance(data, list):
        # 数组编码为长度前缀 + 每个元素的序列化
        result = len(data).to_bytes(8, 'little')
        for item in data:
            result += serialize_to_bcs_like(item)
        return result
    elif isinstance(data, dict):
        # 简化的结构体序列化：按键的字典序排序后序列化
        result = b''
        for key in sorted(data.keys()):
            result += serialize_to_bcs_like(data[key])
        return result
    else:
        raise ValueError(f"Unsupported data type for BCS serialization: {type(data)}")


def move_compatible_hash(data: Any) -> str:
    """
    按照 Move 方式进行哈希：
    1. 对数据进行 BCS 序列化
    2. 使用 SHA256 进行单次哈希
    3. 返回小写 hex 字符串
    """
    # Step 1: BCS 序列化
    bcs_bytes = serialize_to_bcs_like(data)
    
    # Step 2: SHA256 哈希
    hash_bytes = hashlib.sha256(bcs_bytes).digest()
    
    # Step 3: 转换为小写 hex 字符串
    return hash_bytes.hex().lower()


def parse_input_data(input_str: str) -> Any:
    """
    解析输入数据，支持多种格式：
    - JSON 字符串
    - 纯字符串
    - 数字
    """
    input_str = input_str.strip()
    
    # 尝试解析为 JSON
    try:
        return json.loads(input_str)
    except json.JSONDecodeError:
        pass
    
    # 尝试解析为数字
    try:
        if '.' in input_str:
            return float(input_str)
        else:
            return int(input_str)
    except ValueError:
        pass
    
    # 默认作为字符串处理
    return input_str


def main():
    parser = argparse.ArgumentParser(
        description="Move 兼容的哈希处理，使用 BCS 序列化 + SHA256"
    )
    parser.add_argument(
        "data", 
        nargs="?", 
        help="输入数据（JSON、字符串或数字，省略则从 stdin 读取）"
    )
    parser.add_argument(
        "--json", 
        action="store_true",
        help="强制将输入解析为 JSON"
    )
    parser.add_argument(
        "--string", 
        action="store_true",
        help="强制将输入作为字符串处理"
    )
    parser.add_argument(
        "--keep-newline", 
        action="store_true",
        help="保留从 stdin 读取的换行符"
    )
    parser.add_argument(
        "--debug", 
        action="store_true",
        help="显示调试信息（BCS 字节等）"
    )
    
    args = parser.parse_args()
    
    # 获取输入数据
    if args.data is None:
        input_str = sys.stdin.read()
        if not args.keep_newline and input_str.endswith('\n'):
            input_str = input_str[:-1]
    else:
        input_str = args.data
    
    # 解析输入数据
    if args.string:
        data = input_str
    elif args.json:
        try:
            data = json.loads(input_str)
        except json.JSONDecodeError as e:
            print(f"JSON 解析错误: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        data = parse_input_data(input_str)
    
    try:
        # 计算哈希
        hash_result = move_compatible_hash(data)
        
        if args.debug:
            bcs_bytes = serialize_to_bcs_like(data)
            print(f"原始数据: {data}", file=sys.stderr)
            print(f"数据类型: {type(data)}", file=sys.stderr)
            print(f"BCS 字节: {bcs_bytes.hex()}", file=sys.stderr)
            print(f"BCS 长度: {len(bcs_bytes)}", file=sys.stderr)
            print(f"SHA256 哈希: {hash_result}", file=sys.stderr)
            print("---", file=sys.stderr)
        
        print(hash_result)
        
    except Exception as e:
        print(f"处理错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
