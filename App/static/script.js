document.addEventListener('DOMContentLoaded', () => {
    // Animation is handled by CSS on page load.
    // Adding a click handler to replay the animation if desired.

    const container = document.querySelector('.ipad-container');
    const shadow = document.querySelector('.shadow');

    document.body.addEventListener('click', () => {
        // Simple replay mechanism: remove animations and re-add them
        container.style.animation = 'none';
        container.offsetHeight; /* trigger reflow */
        container.style.animation = 'wakeUp 2.5s cubic-bezier(0.22, 1, 0.36, 1) forwards';

        shadow.style.animation = 'none';
        shadow.offsetHeight;
        shadow.style.animation = 'shadowAnim 2.5s cubic-bezier(0.22, 1, 0.36, 1) forwards';
    });
});
