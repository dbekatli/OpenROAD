#!/bin/bash
# set -o xtrace
OPTS=$(getopt -o gudt --long generate,use,deps,toolchain -n 'orbuild.sh' -- "$@")

if [ $? -ne 0 ]; then
  echo "Failed to parse options" >&2
  exit 1
fi
PGOGEN=false
PGOUSE=false
BUILDDEP=false
BUILD_TOOLCHAIN=false
## Reset the positional parameters to the parsed options
eval set -- "$OPTS"

while true; do
  case "$1" in
    -g | --generate)
      PGOGEN=true
      shift
      ;;
    -u | --use)
      PGOUSE=true
      shift
      ;;
    -d | --deps)
      BUILDDEP=true
      shift
      ;;
    -t | --toolchain)
      BUILD_TOOLCHAIN=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Internal error!"
      exit 1
      ;;
  esac
done

mkdir -p prefix
mkdir -p pgodata

PREFIX=$(realpath prefix) 

CC="$PREFIX/bin/gcc" 
CXX="$PREFIX/bin/g++" 
AR="$PREFIX/bin/gcc-ar" 
RANLIB="$PREFIX/bin/gcc-ranlib" 
#-lboost_serialization -lboost_thread  -DBOOST_SERIALIZATION_DYN_LINK=1"
DEBUG_FLAGS="-g3 -ggdb3"
COMMON_FLAGS="-fPIC ${DEBUG_FLAGS} -march=native -mtune=native -O3 -ftree-vectorize -Wno-coverage-mismatch"
BOOST_FLAGS="-lboost_iostreams -lboost_thread -lboost_serialization"
BOOST_FLAGS=""
LTO_FLAGS="-flto=auto"

DEP_FLAGS="$COMMON_FLAGS $LTO_FLAGS" 
OR_FLAGS="$DEP_FLAGS $BOOST_FLAGS"
# COMMON_FLAGS="-march=native -mtune=native -Og -g -ggdb  -fno-eliminate-unused-debug-symbols -fopenmp -Wno-coverage-mismatch -lboost_iostreams -lboost_thread" 
# LTO_FLAGS=""
PGO_GEN_FLAGS="--coverage  -fprofile-generate=$(realpath ./pgodata) "
PGO_USE_FLAGS="-fprofile-use=$(realpath ./pgodata) -fprofile-correction -fprofile-partial-training"


if [ "$BUILD_TOOLCHAIN" = true ]; then
  CC="gcc-14.2.0" 
  CXX="g++-14.2.0" 
  AR="gcc-ar" 
  RANLIB="gcc-ranlib" 
  if [[ ! -f ${PREFIX}/lib/libmpfr.so ]]; then
    mkdir -p prefix/tmp/mpfr
    cd prefix/tmp/mpfr
    wget -nc https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.2.tar.gz
    tar -xvf mpfr-4.2.2.tar.gz
    cd mpfr-4.2.2
    AR="$AR" RANLIB="$RANLIB"  CC=$CC CXX=$CXX CFLAGS="$COMMON_FLAGS" ./configure  --prefix=$PREFIX
    make -j24
    make install
  fi

  export LD_LIBRARY_PATH=$PREFIX/lib
  if [[ ! -f ${PREFIX}/lib/libmpc.so ]]; then
    mkdir -p prefix/tmp/mpc
    cd prefix/tmp/mpc
    wget -nc https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz
    tar -xvf mpc-1.3.1.tar.gz
    cd mpc-1.3.1
    AR="$AR" RANLIB="$RANLIB" CC=$CC CXX=$CXX CFLAGS="$COMMON_FLAGS" ./configure  --prefix=$PREFIX --with-mpfr-lib=$PREFIX/lib --with-mpfr-include=$PREFIX/include 
    make -j24
    make install
  fi



  if [[ ! -f ${PREFIX}/bin/gcc ]]; then
    mkdir -p prefix/tmp/gcc
    git clone https://github.com/gcc-mirror/gcc.git prefix/tmp/gcc --branch=releases/gcc-14.3.0
    cd prefix/tmp/gcc 
    
    ./configure \
                --prefix=$PREFIX \
                --enable-languages=c,c++,lto \
                --with-diagnostics-color=always \
                --enable-default-pie \
                --with-build-config=bootstrap-lto \
                --enable-lto \
                --enable-plugin \
                --disable-multilib \
                --enable-shared \
                --enable-bootstrap \
                --enable-threads=posix \
                --with-mpfr-lib=$PREFIX/lib \
                --with-mpfr-include=$PREFIX/include \
                --with-mpc-lib=$PREFIX/lib

    make -O STAGE1_CFLAGS="$COMMON_FLAGS" BOOT_CFLAGS="$COMMON_FLAGS" -j24 
    make install
  fi

  # mkdir -p prefix/tmp/glibc
  # git clone https://github.com/bminor/glibc.git prefix/tmp/glibc --branch=glibc-2.38
  # cd prefix/tmp/glibc
  # mkdir build
  # cd build
  # CC=$CC CXX=$CXX CFLAGS="$COMMON_FLAGS"  CXXFLAGS="$COMMON_FLAGS" ../configure --prefix=$PREFIX  --host=x86_64-linux-gnu --build=x86_64-linux-gnu 
  # make -j24 
  # make install



  exit
fi

delete_dependensies() {
  read -p "Delete deps to force rebuild?" -n 1 -r
  echo    # (optional) move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
      rm -rf prefix/bin/cmake
      rm -rf prefix/bin/bison
      rm -rf prefix/bin/swig
      rm -rf prefix/include/boost/version.hpp
      rm -rf prefix/include/eigen3
      rm -rf prefix/include/coin/
      rm -rf prefix/include/cudd.h 
      rm -rf prefix/include/lemon/config.h
      rm -rf prefix/cusp
      rm -rf prefix/include/spdlog
      rm -rf prefix/include/gtest
      rm -rf prefix/lib64/libortools*
  fi
}
install_compressors() {
  mkdir -p $PREFIX/tmp/zlib
  cd $PREFIX/tmp/zlib
  wget https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
  tar -xvf zlib-1.3.1.tar.gz
  cd zlib-1.3.1 
  AR="$AR" RANLIB="$RANLIB" CC="${CC}" CXX="${CXX}" CFLAGS="${DEP_FLAGS} -ffat-lto-objects" CXXFLAGS="${DEP_FLAGS} -ffat-lto-objects" ./configure --prefix=$PREFIX 
  AR="$AR" RANLIB="$RANLIB" CC="${CC}" CXX="${CXX}" CFLAGS="${DEP_FLAGS} -ffat-lto-objects" CXXFLAGS="${DEP_FLAGS} -ffat-lto-objects" make -j12
  make install PREFIX=$PREFIX

  mkdir -p $PREFIX/tmp/bzip2
  cd $PREFIX/tmp/bzip2
  wget https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
  tar -xvf bzip2-1.0.8.tar.gz
  cd bzip2-1.0.8
  AR="$AR" RANLIB="$RANLIB" CC="${CC}" CXX="${CXX}" CFLAGS=${DEP_FLAGS} CXXFLAGS=${DEP_FLAGS} PREFIX=$PREFIX make -f Makefile-libbz2_so
  AR="$AR" RANLIB="$RANLIB" CC="${CC}" CXX="${CXX}" CFLAGS=${DEP_FLAGS} CXXFLAGS=${DEP_FLAGS} PREFIX=$PREFIX make bzip2 bzip2recover -j12
  make install PREFIX=$PREFIX
}
install_dependencies () {
  install_compressors
  cd $PREFIX
  cd ..
  AR="$AR" RANLIB="$RANLIB" CC="${CC}" CXX="${CXX}" CFLAGS=${COMMON_FLAGS} CXXFLAGS=${COMMON_FLAGS} source ./etc/DependencyInstaller.sh -common -prefix=$(realpath ./prefix) -constant-build-dir
}

install_OR () {
    buildscript="$(realpath ./etc/Build.sh)"
    prefixfile="$(realpath openroad_deps_prefixes.txt)"
    PATH="$PREFIX:$PATH"
    source "$buildscript"  -gpu  -cmake="-DCMAKE_BUILD_TYPE=Release -DENABLE_TESTS=OFF  -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DLINK_TIME_OPTIMIZATION=1  -DPython3_EXECUTABLE=/usr/bin/python3.6 -DCMAKE_PREFIX_PATH='${PREFIX}' -DCMAKE_CXX_FLAGS='${OR_FLAGS}' -DCMAKE_C_FLAGS='${OR_FLAGS}' -DCMAKE_C_COMPILER='${CC}' -DCMAKE_CXX_COMPILER='${CXX}' -DCMAKE_AR=${AR} -DCMAKE_RANLIB=${RANLIB} -DCMAKE_INSTALL_PREFIX=${PREFIX}"
    make -C build install 
}


if [ "$PGOGEN" = true ] && [ "$PGOUSE" = true ]; then
    echo "pgogen and pgouse cant be specified at the same time"
    exit 1
fi

#non pgo install 
if [ "$PGOGEN" = false ] && [ "$PGOUSE" = false ]; then
     if [ "$BUILDDEP" = true ]; then
  
      delete_dependensies
      install_dependencies
      exit
    fi
    install_OR
    exit 
fi

if [ "$PGOGEN" = true ]; then
  DEP_FLAGS="${PGO_GEN_FLAGS} ${DEP_FLAGS}" 
  OR_FLAGS="${PGO_GEN_FLAGS} ${OR_FLAGS}"
  echo AAAAAAAA
  echo $OR_FLAGS
  install_OR
fi

if [ "$PGOUSE" = true ]; then
    if [ -z "$( ls -A 'pgodata' )" ]; then 
        echo "pgo use option specified but pgodata folder is empty"
        exit 1
    fi

    DEP_FLAGS="${DEP_FLAGS} ${PGO_USE_FLAGS}" 
    OR_FLAGS="${OR_FLAGS} ${PGO_USE_FLAGS}"

    
    # if [ "$BUILDDEP" = true ]; then
    #   delete_dependensies
    #   install_dependencies
    #   exit
    # fi
    read -p "will now delete instrumented OR binary, enter to continue, ctrl-c to exit"
    rm -rf build
    install_OR
fi

if [ "$BUILDDEP" = true ]; then
  echo $DEP_FLAGS
  delete_dependensies
  install_dependencies
  exit
fi

#build deps xz



