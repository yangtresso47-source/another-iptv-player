import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Another IPTV Player",
  description: "Free & Open Source",
  sitemap: {
    hostname: "https://another-iptv-player.com",
  },
  head: [
    [
      "script",
      {
        async: "",
        src: "https://www.googletagmanager.com/gtag/js?id=G-7TGBTLKK9R",
      },
    ],
    [
      "script",
      {},
      `
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', 'G-7TGBTLKK9R');
    `,
    ],
  ],
  themeConfig: {
    logo: "/logo.png",
    nav: [
      { text: "Home", link: "/" },
      { text: "Download", link: "/download" },
      { text: "Support", link: "/information" },
    ],
    sidebar: [
      { text: "Information", link: "/information" },
      { text: "FAQ", link: "/faq" },
    ],
    socialLinks: [
      {
        icon: "github",
        link: "https://github.com/bsogulcan/another-iptv-player",
      },
    ],
  },
});
