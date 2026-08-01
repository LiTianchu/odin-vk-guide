package main

import "core:mem"

import vk "vendor:vulkan"

import "libs:vma"

// function pointer for resource processing procedure
Resource_Proc :: #type proc()

Resource :: union {
	// clean up procedures
	Resource_Proc,
	vk.Pipeline,
	vk.PipelineLayout,
	vk.DescriptorPool,
	vk.DescriptorSetLayout,
	vk.ImageView,
	vk.Sampler,
	vk.CommandPool,
	vk.Fence,
	vk.Semaphore,
	vk.Buffer,
	vk.DeviceMemory,
	vma.Allocator,
	Allocated_Image,
}

Deletion_Queue :: struct {
	device:    vk.Device,
	resources: [dynamic]Resource,
	allocator: mem.Allocator,
}

deletion_queue_init :: proc(
	self: ^Deletion_Queue,
	device: vk.Device,
	allocator := context.allocator,
) {
	assert(self != nil, "Invalid 'Deletion_Queue'")
	assert(device != nil, "Invalid 'Device'")

	self.allocator = allocator
	self.device = device
	self.resources = make([dynamic]Resource, self.allocator)
}

deletion_queue_destroy :: proc(self: ^Deletion_Queue) {
	assert(self != nil)
	context.allocator = self.allocator
	deletion_queue_flush(self)
	delete(self.resources)
}

deletion_queue_push :: proc(self: ^Deletion_Queue, resource: Resource) {
	append(&self.resources, resource)
}

deletion_queue_flush :: proc(self: ^Deletion_Queue) {
	assert(self != nil)
	if len(self.resources) == 0 {
		return
	}

	#reverse for &resource in self.resources {
		switch &res in resource {
		case Resource_Proc:
			res()
		case vk.Pipeline:
			vk.DestroyPipeline(self.device, res, nil)
		case vk.PipelineLayout:
			vk.DestroyPipelineLayout(self.device, res, nil)
		case vk.DescriptorPool:
			vk.DestroyDescriptorPool(self.device, res, nil)
		case vk.DescriptorSetLayout:
			vk.DestroyDescriptorSetLayout(self.device, res, nil)
		case vk.ImageView:
			vk.DestroyImageView(self.device, res, nil)
		case vk.Sampler:
			vk.DestroySampler(self.device, res, nil)
		case vk.CommandPool:
			vk.DestroyCommandPool(self.device, res, nil)
		case vk.Fence:
			vk.DestroyFence(self.device, res, nil)
		case vk.Semaphore:
			vk.DestroySemaphore(self.device, res, nil)
		case vk.Buffer:
			vk.DestroyBuffer(self.device, res, nil)
		case vk.DeviceMemory:
			vk.FreeMemory(self.device, res, nil)
		case vma.Allocator:
			vma.DestroyAllocator(res)
		case Allocated_Image:
			destroy_image(res)
		}
	}

	clear(&self.resources)
}
