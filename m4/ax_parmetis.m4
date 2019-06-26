#
# ----------------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <njansson@csc.kth.se> wrote this file. As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return Niclas Jansson
# ----------------------------------------------------------------------------
#

AC_DEFUN([AX_PARMETIS],[
	AC_ARG_WITH([parmetis],
	AS_HELP_STRING([--with-parmetis=DIR],
	[Directory for parmetis]),
	[	   
	if test -d "$withval"; then
		ac_parmetis_path="$withval";
		PARMETIS_LDFLAGS="-L$ac_parmetis_path/lib"  
		PARMETIS_CPPFLAGS="-I$ac_parmetis_path/include"
	fi
	],)

	AC_ARG_WITH([parmetis-libdir],
	AS_HELP_STRING([--with-parmetis-libdir=LIBDIR],
	[Directory for parmetis library]),
	[
	if test -d "$withval"; then
	   ac_parmetis_libdir="$withval"
	fi
	],)

	if test -d "$ac_parmetis_libdir"; then	   
	    PARMETIS_LDFLAGS="-L$ac_parmetis_libdir"  	   
        fi

	if test -d "$ac_parmetis_path"; then
	   CPPFLAGS_SAVED="$CPPFLAGS"
	   LDFLAGS_SAVED="$LDFLAGS"
	   CPPFLAGS="$PARMETIS_CPPFLAGS $CPPFLAGS"
	   LDFLAGS="$PARMETIS_LDFLAGS $LDFLAGS"
	   export CPPFLAGS
	   export LDFLAGS
	fi
			
	AC_LANG(C)
	AC_CHECK_HEADER([parmetis.h],[have_parmetis_h=yes],[have_parmetis_h=no])
	if test x"${have_parmetis_h}" = xno; then
		if test -d "$ac_parmetis_path"; then	
		   CPPFLAGS="$CPPFLAGS_SAVED"
		fi
	fi
	AC_LANG(Fortran)

	AC_CHECK_LIB(parmetis, ParMETIS_V3_PartMeshKway,
			       [have_parmetis=yes;PARMETIS_LIBS="-lparmetis -lmetis"],
			       [have_parmetis=no],[-lmetis])
	AC_SUBST(PARMETIS_LIBS)
	if test x"${have_parmetis}" = xyes; then
	   AC_DEFINE(HAVE_PARMETIS,1,[Define if you have the ParMETIS library.])
	else
		if test -d "$ac_parmetis_path"; then	
		   LDFLAGS="$LDFLAGS_SAVED"
		fi
	fi

])


