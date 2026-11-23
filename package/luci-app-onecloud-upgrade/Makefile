include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-onecloud-upgrade
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=OneCloud upgrade app

LUCI_TITLE:=OneCloud online firmware upgrade
LUCI_DEPENDS:=+fwupgrade-core +fwupgrade-provider-github +fwupgrade-flasher-onecloud +luci-base +jsonfilter
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# luci.mk 内部已经调用 BuildPackage，这里不能再调一次，否则重复定义
