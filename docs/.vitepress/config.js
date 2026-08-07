import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'

export default withMermaid(
  defineConfig({
    title: "AutoPremium Docs",
    description: "Documentation de l'infrastructure Cloud AWS d'AutoPremium",
    base: "/autopremuim-terraform-infra/",
    head: [
      ['style', {}, `
        h1 img, h2 img, h3 img, h4 img, h5 img {
          display: inline-block !important;
          vertical-align: middle;
        }
      `]
    ],
    themeConfig: {
      logo: 'https://unpkg.com/lucide-static@latest/icons/car.svg',
      nav: [
        { text: 'Accueil', link: '/' },
        { text: 'Dépôt GitHub', link: 'https://github.com/anne7076/autopremuim-terraform-infra' }
      ],
      sidebar: [
        {
          text: 'Infrastructure AWS',
          items: [
            { text: 'Introduction', link: '/' },
            { text: '1. Fondations Réseau (VPC)', link: '/01-network-foundation' },
            { text: '2. Phase 1 : AutoScaling EC2', link: '/02-ec2-architecture' },
            { text: '3. Phase 2 : ECS Fargate', link: '/03-ecs-fargate-architecture' },
            { text: '4. Pipeline CI/CD', link: '/04-cicd-pipeline' },
            { text: '5. DNS & Routage HTTPS', link: '/05-dns-ssl-routing' }
          ]
        }
      ],
      socialLinks: [
        { icon: 'github', link: 'https://github.com/anne7076/autopremuim-terraform-infra' }
      ],
      footer: {
        message: "Documentation AutoPremium Infrastructure.",
        copyright: "© 2026 AutoPremium. Tous droits réservés."
      }
    }
  })
)
