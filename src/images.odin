package main

import vk "vendor:vulkan"


// transition image layout by using image barrier's synchronization instruction
transition_image_layout :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	current_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
) {
	image_barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
	}

	// layout transition need synchronization instruction
	// describe the synchronization dependency
	image_barrier.srcStageMask = {.ALL_COMMANDS} // all gpu command stages
	image_barrier.srcAccessMask = {.MEMORY_WRITE} // all previous memory writes
	image_barrier.dstStageMask = {.ALL_COMMANDS} // all gpu command stages
	image_barrier.dstAccessMask = {.MEMORY_WRITE, .MEMORY_READ} // future reads or writes

	// specify layout transition
	image_barrier.oldLayout = current_layout
	image_barrier.newLayout = new_layout

	// if the destination layout is a .DEPTH_ATTACHMENT_OPTIMAL, assume the image is a depth image
	// else, assume the image is a color image
	aspect_mask: vk.ImageAspectFlags =
		{.DEPTH} if new_layout == .DEPTH_ATTACHMENT_OPTIMAL else {.COLOR}

	// subresource range selects which portion of the image the operation affects
	image_barrier.subresourceRange = image_subresource_range(aspect_mask)
	image_barrier.image = image

	// package the image barrier into a dependency info
	dep_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &image_barrier,
	}

	// submit the image barrier into the command pipeline
	vk.CmdPipelineBarrier2(cmd, &dep_info)
}
