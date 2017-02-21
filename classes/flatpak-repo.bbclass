# flatpak requires merged / and usr, systemd, and PAM. Unfortunately
# distro features cannot be reliably forced, not even by a layer. Use
# the next best thing.

inherit distro_features_check
REQUIRED_DISTRO_FEATURES_append = " usrmerge systemd pam"

inherit flatpak-variables flatpak-keys

# Declare our extra test cases. Also declare a few extra variables
# we (might eventually) use in our test cases, so we want them
# exported and accessible in builddata. These won't have any effect
# unless test-iot.bbclass in inherited by local.conf or the images.
IOTQA_EXTRA_TESTS += " \
    oeqa.runtime.sanity.flatpak:refkit-image-minimal-flatpak-sdk \
"

IOTQA_EXTRA_BUILDDATA += " \
    IMAGE_BASENAME \
    FLATPAK_IMAGE_PATTERN \
"

#
# generating/populating flatpak repositories from/for images
#

do_flatpakrepo () {
   IMAGE_BASENAME="${@d.getVar('IMAGE_BASENAME')}"
   FLATPAK_IMAGE_PATTERN="${@d.getVar('FLATPAK_IMAGE_PATTERN')}"

   #echo "WORKDIR:          ${@d.getVar('WORKDIR')}"
   #echo "DEPLOY_DIR_IMAGE: ${@d.getVar('DEPLOY_DIR_IMAGE')}"
   #echo "IMGDEPLOYDIR:     ${@d.getVar('IMGDEPLOYDIR')}"
   echo "IMAGE_BASENAME:   $IMAGE_BASENAME"
   echo "IMAGE_NAME:       ${@d.getVar('IMAGE_NAME')}"
   #echo "BUILD_ID:         ${@d.getVar('BUILD_ID')}"
   #echo "D:                ${@d.getVar('D')}"
   #echo "S:                ${@d.getVar('S')}"
   #echo "FLATPAK_DISTRO:   ${@d.getVar('FLATPAK_DISTRO')}"
   #
   #return 0

   # Bail out early if flatpak is not enabled for this image.
   if [ "${FLATPAK_IMAGE_PATTERN%%:*}" == "glob" ]; then
       case $IMAGE_BASENAME in
           ${FLATPAK_IMAGE_PATTERN#glob:}) repo_enabled=yes;;
           *)                              repo_enabled="";;
       esac
   else
       repo_enabled=$(echo $IMAGE_BASENAME | grep "$FLATPAK_IMAGE_PATTERN" || :)
   fi

   if [ -z "$repo_enabled" ]; then
       echo "Flatpak not enabled for $IMAGE_BASENAME, skip repo generation..."
       return 0
   fi

   case $IMAGE_BASENAME in
       *-flatpak-runtime) FLATPAK_RUNTIME=runtime;;
       *-flatpak-sdk)     FLATPAK_RUNTIME=sdk;;
       *)                 FLATPAK_RUNTIME=none;;
   esac

   FLATPAKBASE="${@d.getVar('FLATPAKBASE')}"
   FLATPAK_TOPDIR="${@d.getVar('FLATPAK_TOPDIR')}"
   FLATPAK_TMPDIR="${@d.getVar('FLATPAK_TMPDIR')}"
   FLATPAK_ROOTFS="${@d.getVar('FLATPAK_ROOTFS')}"
   FLATPAK_ARCH="${@d.getVar('FLATPAK_ARCH')}"
   FLATPAK_GPGDIR="${@d.getVar('FLATPAK_GPGDIR')}"
   FLATPAK_GPGID="${@d.getVar('FLATPAK_GPGID')}"
   FLATPAK_REPO="${@d.getVar('FLATPAK_REPO')}"
   FLATPAK_EXPORT="${@d.getVar('FLATPAK_EXPORT')}"
   FLATPAK_DISTRO="${@d.getVar('FLATPAK_DISTRO')}"
   FLATPAK_RUNTIME_IMAGE="${@d.getVar('FLATPAK_RUNTIME_IMAGE')}"

   BUILD_ID="${@d.getVar('BUILD_ID')}"
   VERSION=$(cat $FLATPAK_ROOTFS/etc/version)

   # Generate/populate flatpak/OSTree repository
   $FLATPAKBASE/scripts/populate-repo.sh \
       --gpg-home $FLATPAK_GPGDIR \
       --gpg-id $FLATPAK_GPGID \
       --repo-path $FLATPAK_REPO \
       --repo-mode bare-user \
       --repo-export $FLATPAK_EXPORT \
       --rolling-branch latest-build \
       --image-dir $FLATPAK_ROOTFS \
       --image-base $IMAGE_BASENAME \
       --image-type $FLATPAK_RUNTIME \
       --image-arch $FLATPAK_ARCH \
       --image-version $VERSION \
       --image-buildid $BUILD_ID \
       --tmp-dir $FLATPAK_TMPDIR
}

do_flatpakrepo[depends] += " \
    ostree-native:do_populate_sysroot \
    flatpak-native:do_populate_sysroot \
"

do_flatpakrepo[vardeps] += " \
    FLATPAK_GPGDIR \
    FLATPAK_GPGID \
    FLATPAK_REPO \
    FLATPAK_EXPORT \
    FLATPAK_ROOTFS \
    FLATPAK_RUNTIME \
    FLATPAK_ARCH \
    VERSION \
    BUILD_ID \
"

SSTATETASKS += "do_flatpakrepo"
do_flatpakrepo[sstate-inputdirs]  = "${IMGDEPLOYDIR}"
do_flatpakrepo[sstate-outputdirs] = "${DEPLOY_DIR_IMAGE}"

python do_flatpakrepo_setscene () {
    sstate_setscene(d)
}

addtask do_flatpakrepo_setscene
addtask flatpakrepo after do_rootfs # before do_image

#
# Alternatively we could treat flatpak repositories as just another
# image type. Commenting the explicit addtask above and uncommenting
# the remaining assignments below accomplishes just that.
#
# However, at the moment (our set of) ostree (commands) fails to run
# successfully under pseudo. The initial repo creation and population
# works, but pull fails. I *think* the problem might be that pseudo
# fails to properly handle/track directory-relative locking done by
# fcntl(fd, F_OFD_{[SG]ETLK,SETLKW}, ...).
#
# So we go with the explicit task for the time being... which is also
# much better from the flatpak repo creation speed point of view (no
# pseudo).
#
#IMAGE_CMD_flatpak = "do_flatpakrepo"
#IMAGE_FSTYPES_append = " flatpak"
