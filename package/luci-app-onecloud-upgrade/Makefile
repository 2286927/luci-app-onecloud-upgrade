include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-onecloud-upgrade
PKG_VERSION:=0.1.5
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=OneCloud Upgrade <dev@localhost>

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-onecloud-upgrade
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=OneCloud online firmware upgrade
  DEPENDS:=+luci-base +jsonfilter +fwupgrade-core +fwupgrade-provider-github +fwupgrade-flasher-onecloud
  PKGARCH:=all
endef

define Package/luci-app-onecloud-upgrade/description
  OneCloud 专用在线升级界面：状态、固件源配置、检测/升级、备份与回滚、诊断导出。
  只支持 OneCloud（ImmortalWrt 25.12 / apk / ucode LuCI）。
endef

define Build/Compile
endef

define Package/luci-app-onecloud-upgrade/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/onecloud_upgrade
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/onecloud_upgrade/overview.js \
		$(1)/www/luci-static/resources/view/onecloud_upgrade/overview.js

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-onecloud-upgrade.json \
		$(1)/usr/share/luci/menu.d/luci-app-onecloud-upgrade.json

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-onecloud-upgrade.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-onecloud-upgrade.json

	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/luci.onecloud-upgrade \
		$(1)/usr/libexec/rpcd/luci.onecloud-upgrade
endef

# 普通包定义：不走 luci.mk（SDK 下 luci.mk 的注册不稳，且本包不需要 i18n 机制）
$(eval $(call BuildPackage,luci-app-onecloud-upgrade))
