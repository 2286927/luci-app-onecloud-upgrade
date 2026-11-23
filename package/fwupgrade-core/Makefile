include $(TOPDIR)/rules.mk

PKG_NAME:=fwupgrade-core
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=OneCloud upgrade app

include $(INCLUDE_DIR)/package.mk

define Package/fwupgrade-core
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=OneCloud firmware upgrade core (state machine + lock + manifest)
  DEPENDS:=+ucode +ucode-mod-fs +ucode-mod-uci
  PKGARCH:=all
endef

define Package/fwupgrade-core/description
  OneCloud 专用升级核心：状态机、单实例锁、清单解析、版本判定、日志与恢复判定。
  不包含任何平台写入逻辑，写入由 fwupgrade-flasher-* 提供。
endef

define Build/Compile
endef

define Package/fwupgrade-core/install
	$(INSTALL_DIR) $(1)/usr/libexec/fwupgrade
	$(INSTALL_BIN) ./files/usr/libexec/fwupgrade/fwupgradectl $(1)/usr/libexec/fwupgrade/
	$(INSTALL_BIN) ./files/usr/libexec/fwupgrade/worker.sh $(1)/usr/libexec/fwupgrade/
	$(INSTALL_DATA) ./files/usr/libexec/fwupgrade/lib.sh $(1)/usr/libexec/fwupgrade/
	$(INSTALL_DATA) ./files/usr/libexec/fwupgrade/manifest.uc $(1)/usr/libexec/fwupgrade/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/onecloud-upgrade $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/fwupgrade $(1)/etc/init.d/
endef

$(eval $(call BuildPackage,fwupgrade-core))
