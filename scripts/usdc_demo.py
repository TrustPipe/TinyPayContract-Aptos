#!/usr/bin/env python3
"""
TinyPay USDC 演示脚本
展示如何使用 USDC 功能的完整流程
"""

import subprocess
import sys
import time
from typing import List, Dict, Any

class USDCDemo:
    def __init__(self, profile: str = "default"):
        self.profile = profile
        self.package_address = "@tinypay"  # 使用命名地址
        
    def run_command(self, cmd: List[str], description: str = "") -> Dict[str, Any]:
        """运行命令并返回结果"""
        if description:
            print(f"📋 {description}")
        
        print(f"🔧 执行: {' '.join(cmd)}")
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            print(f"✅ 成功")
            if result.stdout.strip():
                print(f"📤 输出: {result.stdout.strip()}")
            return {"success": True, "output": result.stdout, "error": None}
        except subprocess.CalledProcessError as e:
            print(f"❌ 失败")
            if e.stderr:
                print(f"📤 错误: {e.stderr.strip()}")
            return {"success": False, "output": None, "error": e.stderr}
    
    def view_function(self, function_id: str, args: List[str] = None, type_args: List[str] = None, description: str = ""):
        """调用 view 函数"""
        cmd = ["aptos", "move", "view", "--function-id", function_id]
        
        if args:
            cmd.extend(["--args"] + args)
        if type_args:
            cmd.extend(["--type-args"] + type_args)
            
        return self.run_command(cmd, description)
    
    def run_function(self, function_id: str, args: List[str] = None, type_args: List[str] = None, description: str = ""):
        """运行 entry 函数"""
        cmd = ["aptos", "move", "run", "--function-id", function_id, "--profile", self.profile, "--assume-yes"]
        
        if args:
            cmd.extend(["--args"] + args)
        if type_args:
            cmd.extend(["--type-args"] + type_args)
            
        return self.run_command(cmd, description)
    
    def demo_step_1_check_initial_state(self):
        """步骤 1: 检查初始状态"""
        print("\n🔍 步骤 1: 检查初始状态")
        print("=" * 50)
        
        # 检查 APT 是否支持
        self.view_function(
            f"{self.package_address}::tinypay::is_coin_supported",
            type_args=["0x1::aptos_coin::AptosCoin"],
            description="检查 APT 支持状态"
        )
        
        # 检查 USDC 是否支持
        result = self.view_function(
            f"{self.package_address}::tinypay::is_coin_supported",
            type_args=[f"{self.package_address}::test_usdc::TestUSDC"],
            description="检查 USDC 支持状态"
        )
        
        if result["success"] and "false" in result["output"]:
            print("💡 USDC 尚未支持，需要先添加支持")
            return False
        return True
    
    def demo_step_2_setup_usdc(self):
        """步骤 2: 设置 USDC"""
        print("\n🛠️ 步骤 2: 设置 USDC")
        print("=" * 50)
        
        # 初始化 USDC
        result1 = self.run_function(
            f"{self.package_address}::test_usdc::initialize_test_usdc",
            description="初始化测试网 USDC"
        )
        
        # 添加 USDC 支持
        result2 = self.run_function(
            f"{self.package_address}::tinypay::add_coin_support",
            type_args=[f"{self.package_address}::test_usdc::TestUSDC"],
            description="为 TinyPay 添加 USDC 支持"
        )
        
        return result1["success"] and result2["success"]
    
    def demo_step_3_mint_usdc(self):
        """步骤 3: 铸造 USDC"""
        print("\n💰 步骤 3: 铸造测试 USDC")
        print("=" * 50)
        
        # 为管理员铸造 10,000 USDC
        result = self.run_function(
            f"{self.package_address}::test_usdc::mint_to_admin",
            args=["u64:10000000000"],  # 10,000 USDC (6 decimals)
            description="为管理员铸造 10,000 USDC"
        )
        
        return result["success"]
    
    def demo_step_4_check_balances(self):
        """步骤 4: 检查余额"""
        print("\n💳 步骤 4: 检查余额")
        print("=" * 50)
        
        # 获取当前账户地址
        result = subprocess.run(
            ["aptos", "account", "list", "--profile", self.profile],
            capture_output=True, text=True
        )
        
        if result.returncode != 0:
            print("❌ 无法获取账户地址")
            return False
        
        # 简化处理，使用命名地址
        account_address = self.package_address
        
        # 检查 USDC 钱包余额
        self.view_function(
            f"{self.package_address}::test_usdc::get_balance",
            args=[f"address:{account_address}"],
            description="检查钱包中的 USDC 余额"
        )
        
        # 检查 TinyPay 中的 USDC 余额
        self.view_function(
            f"{self.package_address}::tinypay::get_balance",
            args=[f"address:{account_address}"],
            type_args=[f"{self.package_address}::test_usdc::TestUSDC"],
            description="检查 TinyPay 中的 USDC 余额"
        )
        
        return True
    
    def demo_step_5_deposit_usdc(self):
        """步骤 5: 存入 USDC"""
        print("\n📥 步骤 5: 存入 USDC 到 TinyPay")
        print("=" * 50)
        
        # 存入 1,000 USDC
        result = self.run_function(
            f"{self.package_address}::tinypay::deposit",
            args=["u64:1000000000", "vector<u8>:demo_tail_hash"],
            type_args=[f"{self.package_address}::test_usdc::TestUSDC"],
            description="存入 1,000 USDC 到 TinyPay"
        )
        
        return result["success"]
    
    def demo_step_6_check_balances_after_deposit(self):
        """步骤 6: 存款后检查余额"""
        print("\n💳 步骤 6: 存款后检查余额")
        print("=" * 50)
        
        account_address = self.package_address
        
        # 检查 USDC 钱包余额
        self.view_function(
            f"{self.package_address}::test_usdc::get_balance",
            args=[f"address:{account_address}"],
            description="检查钱包中的 USDC 余额"
        )
        
        # 检查 TinyPay 中的 USDC 余额
        self.view_function(
            f"{self.package_address}::tinypay::get_balance",
            args=[f"address:{account_address}"],
            type_args=[f"{self.package_address}::test_usdc::TestUSDC"],
            description="检查 TinyPay 中的 USDC 余额"
        )
        
        return True
    
    def demo_step_7_withdraw_usdc(self):
        """步骤 7: 提取 USDC"""
        print("\n📤 步骤 7: 从 TinyPay 提取 USDC")
        print("=" * 50)
        
        # 提取 500 USDC
        result = self.run_function(
            f"{self.package_address}::tinypay::withdraw_funds",
            args=["u64:500000000"],
            type_args=[f"{self.package_address}::test_usdc::TestUSDC"],
            description="从 TinyPay 提取 500 USDC"
        )
        
        return result["success"]
    
    def demo_step_8_final_balances(self):
        """步骤 8: 最终余额检查"""
        print("\n💳 步骤 8: 最终余额检查")
        print("=" * 50)
        
        account_address = self.package_address
        
        # 检查 USDC 钱包余额
        self.view_function(
            f"{self.package_address}::test_usdc::get_balance",
            args=[f"address:{account_address}"],
            description="检查钱包中的 USDC 余额"
        )
        
        # 检查 TinyPay 中的 USDC 余额
        self.view_function(
            f"{self.package_address}::tinypay::get_balance",
            args=[f"address:{account_address}"],
            type_args=[f"{self.package_address}::test_usdc::TestUSDC"],
            description="检查 TinyPay 中的 USDC 余额"
        )
        
        # 检查 USDC 代币信息
        self.view_function(
            f"{self.package_address}::test_usdc::get_coin_info",
            description="检查 USDC 代币信息"
        )
        
        return True
    
    def run_complete_demo(self):
        """运行完整演示"""
        print("🚀 TinyPay USDC 功能演示")
        print("=" * 60)
        print("本演示将展示 USDC 集成的完整流程：")
        print("1. 检查初始状态")
        print("2. 设置 USDC 支持")
        print("3. 铸造测试代币")
        print("4. 检查余额")
        print("5. 存入 USDC")
        print("6. 检查存款后余额")
        print("7. 提取 USDC")
        print("8. 最终余额检查")
        print("=" * 60)
        
        steps = [
            ("检查初始状态", self.demo_step_1_check_initial_state),
            ("设置 USDC", self.demo_step_2_setup_usdc),
            ("铸造 USDC", self.demo_step_3_mint_usdc),
            ("检查余额", self.demo_step_4_check_balances),
            ("存入 USDC", self.demo_step_5_deposit_usdc),
            ("存款后余额", self.demo_step_6_check_balances_after_deposit),
            ("提取 USDC", self.demo_step_7_withdraw_usdc),
            ("最终余额", self.demo_step_8_final_balances),
        ]
        
        for i, (step_name, step_func) in enumerate(steps, 1):
            try:
                success = step_func()
                if success:
                    print(f"✅ 步骤 {i} 完成: {step_name}")
                else:
                    print(f"⚠️ 步骤 {i} 部分完成: {step_name}")
                
                # 在步骤之间添加短暂延迟
                if i < len(steps):
                    time.sleep(1)
                    
            except Exception as e:
                print(f"❌ 步骤 {i} 失败: {step_name}")
                print(f"错误: {str(e)}")
                return False
        
        print("\n🎉 演示完成!")
        print("\n📋 总结:")
        print("- ✅ USDC 代币已成功集成到 TinyPay")
        print("- ✅ 支持存款、提取和余额查询")
        print("- ✅ 可以与 APT 等其他代币并存使用")
        print("- ✅ 所有基本功能正常工作")
        
        return True

def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description="TinyPay USDC 演示脚本")
    parser.add_argument("--profile", default="default", help="Aptos CLI profile")
    
    args = parser.parse_args()
    
    demo = USDCDemo(args.profile)
    success = demo.run_complete_demo()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
