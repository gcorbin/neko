#
# ----------------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <njansson@kth.se> wrote this file. As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return Niclas Jansson
# ----------------------------------------------------------------------------
#

AC_DEFUN([AX_OPENCL],[
	AC_ARG_WITH([opencl],
		    AC_HELP_STRING([--with-opencl=DIR],
		    [Compile with OpenCL backend]),
		    [
   		    if test -d "$withval"; then
		       ac_opencl_path="$withval";
		       OPENCL_LDFLAGS="-L$ac_opencl_path/lib"
		    fi
		    ], [with_opencl=no])
	opencl_bcknd="0"
	if test "x${with_opencl}" != xno; then
	        if test -d "$ac_hip_path"; then
	   	   CPPFLAGS_SAVED="$CPPFLAGS"
		   LDFLAGS_SAVED="$LDFLAGS"
		   CPPFLAGS="$OPENCL_CPPFLAGS $CPPFLAGS"
		   LDFLAGS="$OPENCL_LDFLAGS $LDFLAGS"
		   export CPPFLAGS
		   export LDFLAGS
		fi

		AC_LANG_PUSH([C])
		AC_LANG_ASSERT([C])
		LIBS_SAVED="$LIBS"
		LIBS="-framework OpenCL $LIBS"
		AC_MSG_CHECKING([for OpenCL])
		AC_LINK_IFELSE([AC_LANG_SOURCE([
		#include <OpenCL/opencl.h>
		int main(void) {
		    clGetPlatformIDs(0, NULL, NULL);
		}
		])],
		[have_opencl=yes],[have_opencl=no])
		
		AC_SUBST(have_opencl)		
		if test x"${have_opencl}" = xyes; then		   
                   opencl_bcknd="1"
		   AC_DEFINE(HAVE_OPENCL,1,[Define if you have OpenCL.])
		   AC_MSG_RESULT([yes])	
		else
		   AC_MSG_ERROR([OpenCL not found])
		fi
		AC_LANG_POP([C])
	fi
	AC_SUBST(opencl_bcknd)	
])