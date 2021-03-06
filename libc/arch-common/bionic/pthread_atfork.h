/*
 * Copyright (C) 2015 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <android/api-level.h>

// __register_atfork wasn't available until android-23. We need to build a
// pre-23 and 23+ version of crtbegin.
#if __ANDROID_API__ >= __ANDROID_API_M__

extern void* __dso_handle;

extern int __register_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void), void* dso);

#ifndef _LIBC
// Libc used to export this in previous versions, therefore it needs
// to remain global for binary compatibility.
__attribute__ ((visibility ("hidden")))
#endif
int pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void)) {
  return __register_atfork(prepare, parent, child, &__dso_handle);
}

#endif  /* __ANDROID_API__ >= __ANDROID_API_M__ */
