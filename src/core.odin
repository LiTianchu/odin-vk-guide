package main

import intr "base:intrinsics"
import "base:runtime"
import "core:log"

import vk "vendor:vulkan"

@(require_results)
vk_check :: #force_inline proc(
	res: vk.Result,
	message := "Detected Vulkan error",
	loc := #caller_location, // compiler directive to get file name, proc name, line and col numbers where this func is called
) -> bool {
	if intr.expect(res, vk.Result.SUCCESS) == .SUCCESS {return true}

	log.errorf("[Vulkan Error] %s: %v", message, res)
	runtime.print_caller_location(loc)
	return false
}
