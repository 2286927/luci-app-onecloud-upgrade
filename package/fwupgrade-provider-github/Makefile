include $(TOPDIR)/rules.mk

PKG_NAME:=fwupgrade-provider-github
PKG_VERSION:=0.1.6
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/fwupgrade-provider-github
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=fwupgrade provider: GitHub Release / static HTTPS / local file
  DEPENDS:=+fwupgrade-core
  PKGARCH:=all
endef

define Package/fwupgrade-provider-github/description
  把 GitHub Release（或静态目录、本地文件）翻译成统一 manifest.json。
  优先使用 release 内自带的 manifest.json；没有时按配置的资产名合成（兼容模式）。
endef

define Build/Compile
endef

define Package/fwupgrade-provider-github/install
	$(INSTALL_DIR) $(1)/usr/libexec/fwupgrade/providers
	$(INSTALL_BIN) ./files/usr/libexec/fwupgrade/providers/github.sh $(1)/usr/libexec/fwupgrade/providers/
	$(INSTALL_BIN) ./files/usr/libexec/fwupgrade/providers/static-https.sh $(1)/usr/libexec/fwupgrade/providers/
	$(INSTALL_BIN) ./files/usr/libexec/fwupgrade/providers/local-file.sh $(1)/usr/libexec/fwupgrade/providers/
	$(INSTALL_DATA) ./files/usr/libexec/fwupgrade/ghrelease.uc $(1)/usr/libexec/fwupgrade/
endef

$(eval $(call BuildPackage,fwupgrade-provider-github))
