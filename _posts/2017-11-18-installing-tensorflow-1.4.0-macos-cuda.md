---
layout:     post
title:      Installing TensorFlow 1.4.0 on macOS with CUDA support
date:       2017-11-18 20:30:00
summary:    Google dropped GPU support on macOS since TensorFlow 1.2. Here's how to get it back on the latest versions of TensorFlow, CUDA 9, cuDNN 7 and macOS High Sierra.
categories: tutorial tensorflow machine-learning deep-learning gpu
hackernews: 15730318
---

Since version 1.2, Google [dropped GPU support](https://www.tensorflow.org/install/install_mac) on macOS from TensorFlow.

It's understandable. As of today, the [last Mac that integrated an nVidia GPU](https://support.apple.com/kb/SP704?locale=en_US) was released in 2014. *Only* their latest operating system, macOS High Sierra, supports external GPUs via Thunderbolt 3.[^1] Who doesn't have the money to get one of the latest MacBook Pro, plus an external GPU enclosure, plus a GPU, 💸 *has to* purchase an [old MacPro](https://support.apple.com/kb/SP652?viewlocale=en_US&locale=en_US) and fit a GPU in there. Any way you see it, it's *quite a niche market*.


At least *officially*.

There's another community that Google forgot. That, is the *Hackintosh* community. At the time of writing, there are 1,475,600 members and 1,510,374 messages in [tonymacx86.com's forums](https://www.tonymacx86.com/forums/), one of the biggest forums for Hackintosh users. That is not a small community. Maybe Google didn't forget. Maybe they fear endorsing a violation of Apple’s licensing agreement.

Whatever the reason, TensorFlow isn't supported on CUDA GPUs on macOS.

Here's how to get that back.

## Clone the TensorFlow repository

```bash
git clone https://github.com/tensorflow/tensorflow
cd tensorflow
git checkout tags/v1.4.0
```

## Prepare the environment

If you do not have *homebrew* installed, install it by following [these instructions](https://brew.sh).

After installing brew, install GNU coreutils, python3, gcc 7[^2], and bazel by issuing the following command:

```bash
brew install coreutils python3 gcc bazel
```

Now you can install TensorFlow's Python dependencies by using pip:
```bash
pip3 install six numpy wheel
```

### CUDA and Xcode
It's time to install [CUDA](https://developer.nvidia.com/cuda) and [cuDNN](https://developer.nvidia.com/cudnn).

Note that CUDA 9.0 is not yet compatible with Xcode 9.x. You can check the compatible Xcode version with the latest CUDA release in [CUDA's official documentation](http://docs.nvidia.com/cuda/cuda-installation-guide-mac-os-x/index.html).

[Here](https://developer.apple.com/download/more/)'s the download page for old Xcode versions. At the time of writing, the latest compatible Xcode with CUDA 9.0 is [Xcode 8.3.3](https://download.developer.apple.com/Developer_Tools/Xcode_8.3.3/Xcode8.3.3.xip). I recommend you to not overwrite the latest Xcode, or homebrew will complain that you have outdated tools. Rather, install the older version in another folder, then tell the system to use that one for now[^3]:

```bash
sudo xcode-select -s /Applications/Xcode\ 8.3.3/Xcode.app
```

cuDNN doesn't have an installer, so we need to extract it and copy it to CUDA's folder by exeuting:

```bash
tar xvf cudnn-*.tgz
sudo cp -rv cuda/* /usr/local/cuda/
```

## Patching TensorFlow

Since dropping support for macOS, TensorFlow consequently dropped support for [clang](http://clang.llvm.org/), macOS default compiler and the one included in Xcode.

With the first patch we can restore compatibility, while with the second we will use [libgomp](https://gcc.gnu.org/onlinedocs/libgomp/) from gcc 7. You can download the following patches [here](https://gist.github.com/crmne/474b44eca214e1c8238f52b21d209dcb/archive/master.zip).

{% gist 474b44eca214e1c8238f52b21d209dcb %}

Extract them in the `tensorflow` folder and patch TensorFlow by issuing the following command:

```bash
for i in *.patch; do patch -p1 < $i; done
```

## Configure the installation

In a moment you'll configure TensorFlow by running the `configure` script (naturally), but before that you'll need to note the following:

* Your CUDA GPU Compute Capability, which you can check [here](https://developer.nvidia.com/cuda-gpus). For example, a GTX 1070 has Compute Capability 6.1
* The location of the python3 executable, by running `which python3`. You can copy this value to the clipboard by running `which python3 | pbcopy`
* The CUDA and cuDNN versions you have, e.g. 9.0 and 7, respectively
* The gcc that should be used by nvcc as the host compiler should be `/usr/bin/gcc`. See footnote[^2].

Now you are ready to answer `configure`'s questions yourself. Here's an example run:

{% gist a22858264d68dd9fe935fc4ee48e0453 %}

## Compile TensorFlow

Before starting to compile TensorFlow, we'll need to tell bazel to pass around the correct environment variables that tell the linker to link with CUDA.

Compiling everything will take a while.

```bash
export CUDA_HOME=/usr/local/cuda
export DYLD_LIBRARY_PATH=/usr/local/cuda/lib:/usr/local/cuda/extras/CUPTI/lib
export LD_LIBRARY_PATH=$DYLD_LIBRARY_PATH
export PATH=$DYLD_LIBRARY_PATH:$PATH
export flags="--config=cuda --config=opt"
bazel build $flags --action_env PATH --action_env LD_LIBRARY_PATH --action_env DYLD_LIBRARY_PATH //tensorflow/tools/pip_package:build_pip_package
```

## Install pip package

If everything went well, you can finally install TensorFlow in the following way:

```bash
bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg
pip3 install -U /tmp/tensorflow_pkg/tensorflow-1.4.0-*.whl
```

## Validate your installation

Validate your TensorFlow installation by doing the following:

Change directory (`cd`) to any directory on your system other than the tensorflow subdirectory from which you invoked the `configure` command.

Prepare the environment for running CUDA jobs:

```bash
export CUDA_HOME=/usr/local/cuda
export DYLD_LIBRARY_PATH=/usr/local/cuda/lib:/usr/local/cuda/extras/CUPTI/lib
export LD_LIBRARY_PATH=$DYLD_LIBRARY_PATH
```

Consider writing those exports to your `.bashrc`, to have your environment ready all the time.

Now invoke python:

```bash
python3
```

and enter the following short program inside the python interactive shell:

```python
import tensorflow as tf
hello = tf.constant('Hello, TensorFlow!')
sess = tf.Session()
print(sess.run(hello))
```

If the system outputs the following, then you are ready to begin writing TensorFlow programs!

```
Hello, TensorFlow!
```

[^1]: macOS High Sierra was released Sept. 25 2017, a few months later than TensorFlow 1.2, June 15 2017
[^2]: gcc-7 is only needed since libgomp is missing from a standard macOS install
[^3]: Note that you can switch back to the latest Xcode with: ```sudo xcode-select -s /Applications/Xcode.app```
