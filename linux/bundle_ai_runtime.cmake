# flutter_gemma 0.12.x invokes an external unzip command and treats extraction
# failures as warnings. Extract with CMake itself and fail if AI cannot be bundled.
set(_archive "${CMAKE_BINARY_DIR}/flutter_gemma_resources/data/litertlm-server.jar")
set(_output "${CMAKE_INSTALL_PREFIX}/lib/litertlm")
cmake_host_system_information(RESULT _host_arch QUERY OS_PLATFORM)
if(_host_arch MATCHES "^(x86_64|amd64|AMD64)$")
  set(_arch "linux-x86_64")
elseif(_host_arch MATCHES "^(aarch64|arm64)$")
  set(_arch "linux-aarch64")
else()
  message(FATAL_ERROR "Unsupported LiteRT-LM Linux architecture")
endif()
set(_member "com/google/ai/edge/litertlm/jni/${_arch}/liblitertlm_jni.so")
set(_temp "${CMAKE_BINARY_DIR}/majika_ai_native")
file(MAKE_DIRECTORY "${_temp}" "${_output}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xf "${_archive}" "${_member}"
  WORKING_DIRECTORY "${_temp}" RESULT_VARIABLE _result)
if(NOT _result EQUAL 0 OR NOT EXISTS "${_temp}/${_member}")
  message(FATAL_ERROR "Could not extract the bundled LiteRT-LM native runtime")
endif()
file(INSTALL "${_temp}/${_member}" DESTINATION "${_output}")
# This JNI build links the Vulkan loader even for CPU inference. Include it in
# the runtime's own LD_LIBRARY_PATH, so end users need no runtime installation.
find_library(_vulkan_loader NAMES vulkan libvulkan.so.1
  HINTS "$ENV{MAJIKA_VULKAN_LIBRARY_DIR}")
if(NOT _vulkan_loader)
  message(FATAL_ERROR "Install the Vulkan loader development package (or use nix develop) to bundle on-device AI")
endif()
get_filename_component(_vulkan_real "${_vulkan_loader}" REALPATH)
file(INSTALL "${_vulkan_real}" DESTINATION "${_output}" RENAME libvulkan.so.1)
file(READ "${_vulkan_real}" _elf_header LIMIT 5 HEX)
if(NOT _elf_header STREQUAL "7f454c4602")
  message(FATAL_ERROR "The Vulkan loader must match the 64-bit LiteRT-LM runtime")
endif()
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/../third_party/Vulkan-Loader/LICENSE.txt"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/data/licenses/Vulkan-Loader")
