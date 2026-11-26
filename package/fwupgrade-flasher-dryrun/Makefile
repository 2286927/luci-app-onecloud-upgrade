include $(TOPDIR)/rules.mk

PKG_NAME:=fwupgrade-flasher-dryrun
PKG_VERSION:=0.1.5
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/fwupgrade-flasher-dryrun
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=fwupgrade flasher: dry-run (never writes)
  DEPENDS:=+fwupgrade-core
  PKGARCH:=all
endef

define Package/fwupgrade-flasher-dryrun/description
  只跑预检与阶段模拟、永不写盘的 flasher。用于 CI 与新设备接入验证。
endef

define Build/Compile
endef

define Package/fwupgrade-flasher-dryrun/install
	$(INSTALL_DIR) $(1)/usr/libexec/fwupgrade/flashers
	$(INSTALL_BIN) ./files/usr/libexec/fwupgrade/flashers/dryrun.sh $(1)/usr/libexec/fwupgrade/flashers/
endef

$(eval $(call BuildPackage,fwupgrade-flasher-dryrun))
