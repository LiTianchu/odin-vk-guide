package main

import intr "base:intrinsics"
import "base:runtime"
import "core:log"
import "libs:vma"

import vk "vendor:vulkan"

Allocated_Image :: struct {
	device:       vk.Device,
	image:        vk.Image,
	image_view:   vk.ImageView,
	image_extent: vk.Extent3D,
	image_format: vk.Format,
	allocator:    vma.Allocator,
	allocation:   vma.Allocation,
}

destroy_image :: proc(self: Allocated_Image) {
	vk.DestroyImageView(self.device, self.image_view, nil)
	vma.DestroyImage(self.allocator, self.image, self.allocation)
}


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
