include $(TOPDIR)/rules.mk

PKG_NAME:=fwupgrade-flasher-onecloud
PKG_VERSION:=0.1.5
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/fwupgrade-flasher-onecloud
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=fwupgrade flasher: OneCloud eMMC (delegates to /usr/bin/upgrade)
  DEPENDS:=+fwupgrade-core
  PKGARCH:=all
endef

define Package/fwupgrade-flasher-onecloud/description
  OneCloud 的唯一写入实现：预检后委托 /usr/bin/upgrade 执行 check/reboot，
  不自建写入逻辑（现网脚本已吸收并发、混合态、爆盘三类事故）。
endef

define Build/Compile
endef

define Package/fwupgrade-flasher-onecloud/install
	$(INSTALL_DIR) $(1)/usr/libexec/fwupgrade/flashers
	$(INSTALL_BIN) ./files/usr/libexec/fwupgrade/flashers/onecloud.sh $(1)/usr/libexec/fwupgrade/flashers/
endef

$(eval $(call BuildPackage,fwupgrade-flasher-onecloud))
