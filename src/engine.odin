package main

import "base:runtime"
import "core:log"
import "vendor:glfw"
import vk "vendor:vulkan"

import "libs:vkb"

TITLE :: "My Renderer"

DEFAULT_WINDOW_EXTENT :: vk.Extent2D{1280, 678}

Engine :: struct {
	window:                glfw.WindowHandle,
	window_extent:         vk.Extent2D,
	is_initialized:        bool,
	stop_rendering:        bool,
	vk_instance:           vk.Instance,
	vk_physical_device:    vk.PhysicalDevice,
	vk_surface:            vk.SurfaceKHR,
	vk_device:             vk.Device,
	vkb:                   struct {
		instance:        vkb.Instance,
		physical_device: vkb.Physical_Device,
		device:          vkb.Device,
		swapchain:       vkb.Swapchain,
	},

	// swap chain
	vk_swapchain:          vk.SwapchainKHR,
	swapchain_format:      vk.Format,
	swapchain_extent:      vk.Extent2D,
	swapchain_images:      []vk.Image,
	swapchain_image_views: []vk.ImageView,
}

@(private)
g_logger: log.Logger

@(require_results)
engine_init :: proc(self: ^Engine) -> (ok: bool) {
	ensure(self != nil, "Invalid Engine Object")
	g_logger = context.logger

	self.window_extent = DEFAULT_WINDOW_EXTENT

	// 0. Create GLFW Window
	self.window = create_window(
		TITLE,
		self.window_extent.width,
		self.window_extent.height,
	) or_return

	defer if !ok {
		destroy_window(self.window)
	}

	glfw.SetWindowUserPointer(self.window, self)
	glfw.SetFramebufferSizeCallback(self.window, callback_framebuffer_size)
	glfw.SetWindowIconifyCallback(self.window, callback_window_minimize)

	log.info("Initializing Vulkan...")
	engine_init_vulkan(self) or_return
	engine_init_commands(self) or_return
	engine_init_sync_structures(self) or_return
	engine_init_swapchain(self) or_return


	self.is_initialized = true

	return true

}


@(require_results)
engine_draw :: proc(self: ^Engine) -> (ok: bool) {
	return true
}

@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
	log.info("Entering main loop...")

	// engine loop
	loop: for !glfw.WindowShouldClose(self.window) {
		glfw.PollEvents()

		if self.stop_rendering {
			glfw.WaitEvents()
			continue
		}

		// draw event
		engine_draw(self) or_return
	}

	log.info("Exiting...")
	return true
}

engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool) {
	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	// 1. Build instance
	log.info("Building Vulkan Instance...")
	VULKAN_TITLE :: "Example Vulkan Application"
	instance_builder: vkb.Instance_Builder
	vkb.instance_builder_init(&instance_builder, ta)
	vkb.instance_builder_set_app_name(&instance_builder, VULKAN_TITLE)

	vkb.instance_builder_require_api_version(&instance_builder, vk.API_VERSION_1_3)

	log.infof("Vulkan Instance %s built successfully!", VULKAN_TITLE)


	// 1.5. Setup Validation Layer
	when ODIN_DEBUG {
		log.info("Debug mode detected, setting up validation layer...")
		vkb.instance_builder_request_validation_layers(&instance_builder)

		default_debug_callback :: proc "system" (
			message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
			message_types: vk.DebugUtilsMessageTypeFlagsEXT,
			p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
			p_user_data: rawptr,
		) -> b32 {
			context = runtime.default_context()
			context.logger = g_logger

			if .WARNING in message_severity {
				log.warnf("[%v]: %s", message_types, p_callback_data.pMessage)
			} else if .ERROR in message_severity {
				log.errorf("[%v]: %s", message_types, p_callback_data.pMessage)
				runtime.debug_trap()
			} else {
				log.infof("[%v]: %s", message_types, p_callback_data.pMessage)
			}

			return false
		}

		vkb.instance_builder_set_debug_callback(&instance_builder, default_debug_callback)
		vkb.instance_builder_set_debug_callback_user_data_pointer(&instance_builder, self)

		VK_LAYER_LUNARG_MONITOR :: "VK_LAYER_LUNARG_monitor"

		info: vkb.System_Info
		info_err := vkb.system_info_init(&info, allocator = ta)
		if info_err != nil {
			log.errorf("Failed to get system info: %#v", info_err)
			return
		}

		if vkb.system_info_is_layer_available(info, VK_LAYER_LUNARG_MONITOR) {
			// FPS counter in the app title bar. Only compatible with the Win32 and XCB windowing systems
			when ODIN_OS == .Windows || ODIN_OS == .Linux {
				vkb.instance_builder_enable_layer(&instance_builder, VK_LAYER_LUNARG_MONITOR)
			}
		}
		log.info("Validation layer set up successfully!")
	}

	vkb_instance_err := vkb.instance_builder_build(&instance_builder, &self.vkb.instance)

	if vkb_instance_err != nil {
		log.errorf("Failed to build instance: %#v", vkb_instance_err)
	}
	defer if !ok {
		vkb.destroy_instance(&self.vkb.instance)
	}

	self.vk_instance = self.vkb.instance.vk_instance

	// 2. Build Window Surface
	log.info("Building Window Surface...")
	vk_check(
		glfw.CreateWindowSurface(self.vk_instance, self.window, nil, &self.vk_surface),
	) or_return
	defer if !ok {
		vkb.destroy_surface(&self.vkb.instance, self.vk_surface)
	}
	log.info("Window Surface built successfully!")

	log.info("Building Vulkan Physical Device handle...")
	features_11 := vk.PhysicalDeviceVulkan11Features {
		shaderDrawParameters = true,
	}

	features_12 := vk.PhysicalDeviceVulkan12Features {
		// allow shaders to directly access buffer memory using GPU addresses
		bufferDeviceAddress = true,
		// enables dynamic indexing of descriptors and more flexible descriptor usage
		descriptorIndexing  = true,
	}

	features_13 := vk.PhysicalDeviceVulkan13Features {
		// eliminates the need for render pass objects, simplifying rendering setup
		dynamicRendering = true,
		// provides improved synchronization primitives with simpler usage patterns
		synchronization2 = true,
	}

	// 3. Build Physical Device (GPU handle)
	// use vk bootstrap to select GPU
	selector: vkb.Physical_Device_Selector
	vkb.physical_device_selector_init(&selector, self.vkb.instance, ta)

	vkb.physical_device_selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
	vkb.physical_device_selector_set_required_features_13(&selector, features_13)
	vkb.physical_device_selector_set_required_features_12(&selector, features_12)
	vkb.physical_device_selector_set_required_features_11(&selector, features_11)
	vkb.physical_device_selector_set_surface(&selector, self.vk_surface)

	vkb_physical_device_err := vkb.physical_device_selector_select(
		&selector,
		&self.vkb.physical_device,
	)

	if vkb_physical_device_err != nil {
		log.errorf("Failed to selector physical device: %#v", vkb_physical_device_err)
		return
	}

	defer if !ok {
		vkb.destroy_physical_device(&self.vkb.physical_device)
	}

	self.vk_physical_device = self.vkb.physical_device.vk_physical_device
	log.info("Vulkan Physical Device handle built successfully!")

	// 4. Build Vulkan Device (GPU driver object)
	// create the final vulkan device
	log.info("Building Vulkan Device...")
	device_builder: vkb.Device_Builder
	vkb.device_builder_init(&device_builder, ta)

	vkb_device_err := vkb.device_builder_build(
		&device_builder,
		&self.vkb.physical_device,
		&self.vkb.device,
	)

	if vkb_device_err != nil {
		log.errorf("Failed to get logical device: %#v", vkb_device_err)
	}
	defer if !ok {
		vkb.destroy_device(&self.vkb.device)
	}

	self.vk_device = self.vkb.device.vk_device
	log.info("Vulkan Device built successfully!")

	return true
}

engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
	engine_create_swapchain(self, self.window_extent) or_return
	return true
}

engine_create_swapchain :: proc(self: ^Engine, extent: vk.Extent2D) -> (ok: bool) {
	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	self.swapchain_format = .B8G8R8A8_UNORM

	// 5. Build swapchain
	log.info("Building Vulkan Swapchain...")
	builder: vkb.Swapchain_Builder
	vkb.swapchain_builder_init(&builder, self.vkb.device, ta)

	vkb.swapchain_builder_set_desired_format(
		&builder,
		{format = self.swapchain_format, colorSpace = .SRGB_NONLINEAR},
	)

	vkb.swapchain_builder_set_desired_present_mode(&builder, .FIFO)

	vkb.swapchain_builder_set_desired_extent(&builder, extent.width, extent.height)
	vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})
	swapchain_err := vkb.swapchain_builder_build(&builder, &self.vkb.swapchain)

	if swapchain_err != nil {
		log.errorf("Failed to build swapchain: %#v", swapchain_err)
		return
	}

	// save built swapchain
	self.vk_swapchain = self.vkb.swapchain.vk_swapchain
	self.swapchain_extent = self.vkb.swapchain.vk_extent

	// get VkImages (image resources)
	swapchain_images, swapchain_images_err := vkb.swapchain_get_images(self.vkb.swapchain)

	if swapchain_images_err != nil {
		log.errorf("Failed to get swapchain images: %#v", swapchain_images_err)
		return
	}

	// image view describes image information such as color format, mip level count
	swapchain_image_views, swapchain_image_views_err := vkb.swapchain_get_image_views(
		self.vkb.swapchain,
	)

	if swapchain_image_views_err != nil {
		log.errorf("Failed to get swapchain image views: %#v", swapchain_image_views_err)
		return
	}

	// save image and image views
	self.swapchain_images = swapchain_images
	self.swapchain_image_views = swapchain_image_views
	log.info("Vulkan Swapchain built successfully!")


	return true
}

engine_destroy_swapchain :: proc(self: ^Engine) {
	vkb.swapchain_destroy_image_views(self.vkb.swapchain, self.swapchain_image_views)
	vkb.destroy_swapchain(&self.vkb.swapchain)
	delete(self.swapchain_image_views)
	delete(self.swapchain_images)
}


engine_cleanup :: proc(self: ^Engine) {
	if !self.is_initialized {
		return
	}

	// need to delete the objects in correct order as they have dependencies
	// in general, they should be deleted in the opposite order of the initialization
	// initialization order: GLFW Window -> VK Instance -> VK Surface -> VK Device -> VK Swapchain
	engine_destroy_swapchain(self)
	vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
	vkb.destroy_device(&self.vkb.device)
	vkb.destroy_physical_device(&self.vkb.physical_device)
	vkb.destroy_instance(&self.vkb.instance)
	destroy_window(self.window)
}

engine_init_commands :: proc(self: ^Engine) -> (ok: bool) {

	return true
}

engine_init_sync_structures :: proc(self: ^Engine) -> (ok: bool) {
	return true
}
