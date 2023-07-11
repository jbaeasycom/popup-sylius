<?php

declare(strict_types=1);

namespace Workouse\PopupPlugin\Controller;

use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Workouse\PopupPlugin\Entity\Popup;

class PopupController extends AbstractController
{
    public function __construct(private readonly EntityManagerInterface $entityManager)
    {}

    public function indexAction(): Response
    {
        /** @var Popup $popup */
        $popup = $this->entityManager->getRepository(Popup::class)->findOneBy(
            [
                'enabled' => true,
            ]
        );

        return $this->render(
            '@WorkousePopupPlugin/shop/index.html.twig',
            [
                'popup' => $popup,
            ]
        );
    }
}
