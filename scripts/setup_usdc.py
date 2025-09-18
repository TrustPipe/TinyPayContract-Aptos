#!/usr/bin/env python3
"""
TinyPay USDC 设置脚本
用于快速设置测试网 USDC 环境
"""

import subprocess
import sys
import json
from typing import List, Dict, Any

class USDCSetup:
    def __init__(self, profile: str = "default"):
        self.profile = profile
        self.package_address = None
        
    def run_command(self, cmd: List[str]) -> Dict[str, Any]:
        """运行命令并返回结果"""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            print(f"✅ 命令执行成功: {' '.join(cmd)}")
            if result.stdout:
                print(f"输出: {result.stdout}")
            return {"success": True, "output": result.stdout, "error": None}
        except subprocess.CalledProcessError as e:
            print(f"❌ 命令执行失败: {' '.join(cmd)}")
            print(f"错误: {e.stderr}")
            return {"success": False, "output": None, "error": e.stderr}
    
    def compile_package(self) -> bool:
        """编译 Move 包"""
        print("🔨 编译 Move 包...")
        result = self.run_command(["aptos", "move", "compile", "--profile", self.profile])
        return result["success"]
    
    def publish_package(self) -> bool:
        """发布 Move 包"""
        print("📦 发布 Move 包...")
        result = self.run_command([
            "aptos", "move", "publish", 
            "--profile", self.profile,
            "--assume-yes"
        ])
        
        if result["success"]:
            # 尝试从输出中提取包地址
            output = result["output"]
            if "Code was successfully deployed" in output:
                # 解析包地址
                lines = output.split('\n')
                for line in lines:
                    if "package" in line.lower() and "0x" in line:
                        # 简单的地址提取
                        parts = line.split()
                        for part in parts:
                            if part.startswith("0x") and len(part) > 10:
                                self.package_address = part
                                break
                        break
        
        return result["success"]
    
    def initialize_usdc(self) -> bool:
        """初始化测试网 USDC"""
        print("🪙 初始化测试网 USDC...")
        result = self.run_command([
            "aptos", "move", "run",
            "--function-id", f"{self.package_address or '@tinypay'}::test_usdc::initialize_test_usdc",
            "--profile", self.profile,
            "--assume-yes"
        ])
        return result["success"]
    
    def add_usdc_support(self) -> bool:
        """为 TinyPay 添加 USDC 支持"""
        print("🔗 为 TinyPay 添加 USDC 支持...")
        result = self.run_command([
            "aptos", "move", "run",
            "--function-id", f"{self.package_address or '@tinypay'}::tinypay::add_coin_support",
            "--type-args", f"{self.package_address or '@tinypay'}::test_usdc::TestUSDC",
            "--profile", self.profile,
            "--assume-yes"
        ])
        return result["success"]
    
    def mint_usdc_to_admin(self, amount: int = 10000000000) -> bool:
        """为管理员铸造 USDC (默认 10,000 USDC)"""
        print(f"💰 为管理员铸造 {amount/1000000} USDC...")
        result = self.run_command([
            "aptos", "move", "run",
            "--function-id", f"{self.package_address or '@tinypay'}::test_usdc::mint_to_admin",
            "--args", f"u64:{amount}",
            "--profile", self.profile,
            "--assume-yes"
        ])
        return result["success"]
    
    def check_usdc_balance(self, address: str = None) -> bool:
        """检查 USDC 余额"""
        if not address:
            # 获取当前 profile 的地址
            result = self.run_command(["aptos", "account", "list", "--profile", self.profile])
            if not result["success"]:
                return False
            # 这里需要解析地址，简化处理
            address = "@tinypay"  # 使用默认地址
        
        print(f"💳 检查 {address} 的 USDC 余额...")
        result = self.run_command([
            "aptos", "move", "view",
            "--function-id", f"{self.package_address or '@tinypay'}::test_usdc::get_balance",
            "--args", f"address:{address}"
        ])
        return result["success"]
    
    def run_tests(self) -> bool:
        """运行测试"""
        print("🧪 运行 USDC 相关测试...")
        result = self.run_command([
            "aptos", "move", "test",
            "--filter", "usdc",
            "--profile", self.profile
        ])
        return result["success"]
    
    def setup_complete_environment(self) -> bool:
        """完整的环境设置"""
        print("🚀 开始设置 TinyPay USDC 环境...\n")
        
        steps = [
            ("编译包", self.compile_package),
            ("发布包", self.publish_package),
            ("初始化 USDC", self.initialize_usdc),
            ("添加 USDC 支持", self.add_usdc_support),
            ("铸造测试 USDC", self.mint_usdc_to_admin),
            ("检查余额", self.check_usdc_balance),
        ]
        
        for step_name, step_func in steps:
            print(f"\n📋 执行步骤: {step_name}")
            if not step_func():
                print(f"❌ 步骤失败: {step_name}")
                return False
            print(f"✅ 步骤完成: {step_name}")
        
        print("\n🎉 USDC 环境设置完成!")
        print("\n📝 接下来你可以:")
        print("1. 使用 tinypay::test_usdc::register 注册账户")
        print("2. 使用 tinypay::test_usdc::mint 铸造测试代币")
        print("3. 使用 tinypay::tinypay::deposit 存入 USDC")
        print("4. 运行测试: aptos move test --filter usdc")
        
        return True

def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description="TinyPay USDC 设置脚本")
    parser.add_argument("--profile", default="default", help="Aptos CLI profile")
    parser.add_argument("--action", choices=[
        "setup", "compile", "publish", "init", "add-support", 
        "mint", "balance", "test"
    ], default="setup", help="要执行的操作")
    parser.add_argument("--amount", type=int, default=10000000000, 
                       help="铸造的 USDC 数量 (默认 10,000 USDC)")
    parser.add_argument("--address", help="检查余额的地址")
    
    args = parser.parse_args()
    
    setup = USDCSetup(args.profile)
    
    if args.action == "setup":
        success = setup.setup_complete_environment()
    elif args.action == "compile":
        success = setup.compile_package()
    elif args.action == "publish":
        success = setup.publish_package()
    elif args.action == "init":
        success = setup.initialize_usdc()
    elif args.action == "add-support":
        success = setup.add_usdc_support()
    elif args.action == "mint":
        success = setup.mint_usdc_to_admin(args.amount)
    elif args.action == "balance":
        success = setup.check_usdc_balance(args.address)
    elif args.action == "test":
        success = setup.run_tests()
    else:
        print(f"❌ 未知操作: {args.action}")
        success = False
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
